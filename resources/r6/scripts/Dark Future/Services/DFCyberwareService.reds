// -----------------------------------------------------------------------------
// DFCyberwareService
// -----------------------------------------------------------------------------
//
// - Service that handles data about equipped Cyberware and their bonuses unique
//   to Dark Future.
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem
}

class DFCyberwareServiceEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFCyberwareService> {
		return DFCyberwareService.Get();
	}
}

public final class DFCyberwareService extends DFSystem {
	private let TransactionSystem: ref<TransactionSystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;

	private let equipmentSystemPlayerData: ref<EquipmentSystemPlayerData>;
	private let cyberwareEquipmentAreas: array<gamedataEquipmentArea>;
	private let equippedCyberwareItemIDs: array<ItemID>;

    private let cyberwareHasSecondHeart: Bool = false;
    private let cyberwareHasSynLungs: Bool = false;
    private let cyberwareHasSynLiver: Bool = false;
    private let cyberwareAlcoholEffectDurationOverride: Float = 0.0;
    private let cyberwareNicotineEffectDurationOverride: Float = 0.0;
	private let cyberwareExertionHydrationChangeBonusMult: Float = 1.0;
	private let cyberwareNerveCostWhenHitBonusMult: Float = 1.0;
	private let cyberwareNerveCostStressBonusMult: Float = 0.0;
	private let cyberwareNerveLossFromNarcoticsBonusMult: Float = 1.0;
	private let cyberwareSecondHeartNerveRestoreAmount: Float = 30.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFCyberwareService> {
		let instance: ref<DFCyberwareService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Services.DFCyberwareService") as DFCyberwareService;
		return instance;
	}

	public final static func Get() -> ref<DFCyberwareService> {
		return DFCyberwareService.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	private final func RegisterListeners() -> Void {}
	private final func UnregisterListeners() -> Void {}
	private final func RegisterAllRequiredDelayCallbacks() -> Void {}
	private final func UnregisterAllDelayCallbacks() -> Void {}
	public final func OnTimeSkipStart() -> Void {}
	public final func OnTimeSkipCancelled() -> Void {}
	public final func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}
	private final func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	private final func DoPostSuspendActions() -> Void {
		this.SetDefaultBonusState();
	}

	private final func DoStopActions() -> Void {}

	private final func DoPostResumeActions() -> Void {
		this.UpdateEquippedCyberwareAndBonuses();
	}
	
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private final func GetSystems() -> Void {
		let gameInstance = GetGameInstance();
		this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
	}

	private final func SetupData() -> Void {
		this.equipmentSystemPlayerData = EquipmentSystem.GetData(this.player);
		this.cyberwareEquipmentAreas = this.equipmentSystemPlayerData.GetAllCyberwareEquipmentAreas();
	}

	private final func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		this.UpdateEquippedCyberwareAndBonuses();
	}

	//
	//	System-Specific Methods
	private final func SetDefaultBonusState() -> Void {
		this.cyberwareHasSecondHeart = false;
		this.cyberwareHasSynLungs = false;
		this.cyberwareHasSynLiver = false;
		this.cyberwareAlcoholEffectDurationOverride = 0.0;
		this.cyberwareNicotineEffectDurationOverride = 0.0;
		this.cyberwareExertionHydrationChangeBonusMult = 1.0;
		this.cyberwareNerveCostStressBonusMult = 0.0;
		this.cyberwareNerveLossFromNarcoticsBonusMult = 1.0;
		this.cyberwareSecondHeartNerveRestoreAmount = 30.0;
	}

    public final func UpdateEquippedCyberwareAndBonuses() -> Void {
		this.UpdateEquippedCyberwareItemIDs(this.equippedCyberwareItemIDs);
		this.UpdateCyberwareBonuses();
	}

    private final func UpdateEquippedCyberwareItemIDs(out itemIDs: array<ItemID>) -> Void {
		ArrayClear(itemIDs);
		
		let i: Int32 = 0;
		while i < ArraySize(this.cyberwareEquipmentAreas) {
			let j: Int32 = 0;
			while j < this.equipmentSystemPlayerData.GetNumberOfSlots(this.cyberwareEquipmentAreas[i]) {
				let currentItemID: ItemID = this.player.GetEquippedItemIdInArea(this.cyberwareEquipmentAreas[i], j);
				if ItemID.IsValid(currentItemID) && this.TransactionSystem.HasItem(this.player, currentItemID) {
					ArrayPush(itemIDs, currentItemID);
				}
				j += 1;
			}
			i += 1;
		}
	}

    private final func UpdateCyberwareBonuses() -> Void {
		// Reset data.
		this.cyberwareExertionHydrationChangeBonusMult = 1.0;
		this.cyberwareNerveCostStressBonusMult = 0.0;
		this.cyberwareNerveLossFromNarcoticsBonusMult = 1.0;
        this.cyberwareAlcoholEffectDurationOverride = 0.0;
        this.cyberwareNicotineEffectDurationOverride = 0.0;
		this.cyberwareHasSecondHeart = false;
		this.cyberwareHasSynLungs = false;
		this.cyberwareHasSynLiver = false;

		let i: Int32 = 0;
		while i < ArraySize(this.equippedCyberwareItemIDs) {
			let itemID: ItemID = this.equippedCyberwareItemIDs[i];
			let cyberwareType: CName = TweakDBInterface.GetCName(ItemID.GetTDBID(itemID) + t".cyberwareType", n"None");
			if NotEquals(cyberwareType, n"None") {
        		let quality: gamedataQuality = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(itemID)).QualityHandle().Type();
				
				if Equals(cyberwareType, n"IronLungs") {
					switch quality {
						case gamedataQuality.Rare:
							this.cyberwareExertionHydrationChangeBonusMult = 0.70; // 30% bonus
							this.cyberwareNicotineEffectDurationOverride = 210.0;
							break;
						case gamedataQuality.RarePlus:
							this.cyberwareExertionHydrationChangeBonusMult = 0.65; // 35% bonus
							this.cyberwareNicotineEffectDurationOverride = 180.0;
							break;
						case gamedataQuality.Epic:
							this.cyberwareExertionHydrationChangeBonusMult = 0.60; // 40% bonus
							this.cyberwareNicotineEffectDurationOverride = 150.0;
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareExertionHydrationChangeBonusMult = 0.55; // 45% bonus
							this.cyberwareNicotineEffectDurationOverride = 120.0;
							break;
						case gamedataQuality.Legendary:
							this.cyberwareExertionHydrationChangeBonusMult = 0.50; // 50% bonus
							this.cyberwareNicotineEffectDurationOverride = 90.0;
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareExertionHydrationChangeBonusMult = 0.45; // 55% bonus
							this.cyberwareNicotineEffectDurationOverride = 60.0;
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareExertionHydrationChangeBonusMult = 0.40; // 60% bonus
							this.cyberwareNicotineEffectDurationOverride = 30.0;
							break;
					}
					this.cyberwareHasSynLungs = true;

				} else if Equals(cyberwareType, n"SynLiver") {
					switch quality {
						case gamedataQuality.Rare:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.60; // 40% bonus
							this.cyberwareAlcoholEffectDurationOverride = 22.5;
							break;
						case gamedataQuality.RarePlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.50; // 50% bonus
							this.cyberwareAlcoholEffectDurationOverride = 22.5;
							break;
						case gamedataQuality.Epic:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.40; // 60% bonus
							this.cyberwareAlcoholEffectDurationOverride = 15.0;
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.30; // 70% bonus
							this.cyberwareAlcoholEffectDurationOverride = 15.0;
							break;
						case gamedataQuality.Legendary:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.20; // 80% bonus
							this.cyberwareAlcoholEffectDurationOverride = 7.5;
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.10; // 90% bonus
							this.cyberwareAlcoholEffectDurationOverride = 7.5;
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.0; // 100% bonus
							this.cyberwareAlcoholEffectDurationOverride = 7.5;
							break;
					}
					this.cyberwareHasSynLiver = true;

				} else if Equals(cyberwareType, n"DetectorRush") { // Adrenaline Converter
					switch quality {
						case gamedataQuality.Common:
							this.cyberwareNerveCostStressBonusMult = 0.15; // 15% bonus
							break;
						case gamedataQuality.CommonPlus:
							this.cyberwareNerveCostStressBonusMult = 0.17; // 17% bonus
							break;
						case gamedataQuality.Uncommon:
							this.cyberwareNerveCostStressBonusMult = 0.19; // 19% bonus
							break;
						case gamedataQuality.UncommonPlus:
							this.cyberwareNerveCostStressBonusMult = 0.21; // 21% bonus
							break;
						case gamedataQuality.Rare:
							this.cyberwareNerveCostStressBonusMult = 0.23; // 23% bonus
							break;
						case gamedataQuality.RarePlus:
							this.cyberwareNerveCostStressBonusMult = 0.25; // 25% bonus
							break;
						case gamedataQuality.Epic:
							this.cyberwareNerveCostStressBonusMult = 0.27; // 27% bonus
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareNerveCostStressBonusMult = 0.29; // 29% bonus
							break;
						case gamedataQuality.Legendary:
							this.cyberwareNerveCostStressBonusMult = 0.31; // 31% bonus
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareNerveCostStressBonusMult = 0.33; // 33% bonus
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareNerveCostStressBonusMult = 0.35; // 35% bonus
							break;
					}
				} else if Equals(cyberwareType, n"SecondHeart") {
					this.cyberwareHasSecondHeart = true;
				}
			}

			i += 1;
		}

		if !this.cyberwareHasSynLungs {
			this.NicotineAddictionSystem.ResetEffectDuration();
		}

		if !this.cyberwareHasSynLiver {
			this.AlcoholAddictionSystem.ResetEffectDuration();
		}

		this.NicotineAddictionSystem.SetNicotineAddictionBackoffDurations();

		DFLog(this.debugEnabled, this, "UpdateCyberwareBonuses Result:");
		DFLog(this.debugEnabled, this, "    cyberwareExertionHydrationChangeBonusMult = " + ToString(this.cyberwareExertionHydrationChangeBonusMult));
		DFLog(this.debugEnabled, this, "    cyberwareNerveCostStressBonusMult = " + ToString(this.cyberwareNerveCostStressBonusMult));
		DFLog(this.debugEnabled, this, "    cyberwareNerveLossFromNarcoticsBonusMult = " + ToString(this.cyberwareNerveLossFromNarcoticsBonusMult));
		DFLog(this.debugEnabled, this, "    cyberwareHasSecondHeart = " + ToString(this.cyberwareHasSecondHeart));
        DFLog(this.debugEnabled, this, "    cyberwareHasSynLungs = " + ToString(this.cyberwareHasSynLungs));
        DFLog(this.debugEnabled, this, "    cyberwareHasSynLiver = " + ToString(this.cyberwareHasSynLiver));
		DFLog(this.debugEnabled, this, "    cyberwareNicotineEffectDurationOverride = " + ToString(this.cyberwareNicotineEffectDurationOverride));
		DFLog(this.debugEnabled, this, "    cyberwareAlcoholEffectDurationOverride = " + ToString(this.cyberwareAlcoholEffectDurationOverride));
	}

    public final func GetHasSecondHeart() -> Bool {
        return this.cyberwareHasSecondHeart;
    }

    public final func GetHasSynLungs() -> Bool {
        return this.cyberwareHasSynLungs;
    }

    public final func GetHasSynLiver() -> Bool {
        return this.cyberwareHasSynLiver;
    }

    public final func GetAlcoholEffectDurationOverride() -> Float {
        return this.cyberwareAlcoholEffectDurationOverride;
    }

    public final func GetNicotineEffectDurationOverride() -> Float {
        return this.cyberwareNicotineEffectDurationOverride;
    }

    public final func GetExertionHydrationChangeBonusMult() -> Float {
        return this.cyberwareExertionHydrationChangeBonusMult;
    }

    public final func GetNerveCostFromStressBonusMult() -> Float {
        return this.cyberwareNerveCostStressBonusMult;
    }

    public final func GetNerveLossFromNarcoticsBonusMult() -> Float {
        return this.cyberwareNerveLossFromNarcoticsBonusMult;
    }

    public final func GetSecondHeartNerveRestoreAmount() -> Float {
        return this.cyberwareSecondHeartNerveRestoreAmount;
    }
}

//
//	Base Game Methods
//

//	RipperDocGameController - Update equipped Cyberware bonuses after leaving the Ripperdoc vendor screen.
//
@wrapMethod(RipperDocGameController)
protected cb func OnBeforeLeaveScenario(userData: ref<IScriptable>) -> Bool {
	let value: Bool = wrappedMethod(userData);

	let CyberwareSystem: ref<DFCyberwareService> = DFCyberwareService.Get();
	CyberwareSystem.UpdateEquippedCyberwareAndBonuses();

	return value;
}