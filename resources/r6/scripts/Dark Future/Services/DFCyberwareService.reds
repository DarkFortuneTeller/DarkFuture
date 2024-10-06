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
    private let cyberwareAlcoholNumbedRequiredStacksOverride: Uint32 = 0u;
    private let cyberwareNicotineEffectDurationOverride: Float = 0.0;
	private let cyberwareNerveCostWhenHitBonusMult: Float = 1.0;
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
		this.debugEnabled = true;
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
		this.cyberwareAlcoholNumbedRequiredStacksOverride = 0u;
		this.cyberwareNicotineEffectDurationOverride = 0.0;
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
		this.cyberwareNerveLossFromNarcoticsBonusMult = 1.0;
        this.cyberwareAlcoholNumbedRequiredStacksOverride = 0u;
        this.cyberwareNicotineEffectDurationOverride = 0.0;
		this.cyberwareHasSecondHeart = false;

		let i: Int32 = 0;
		while i < ArraySize(this.equippedCyberwareItemIDs) {
			let itemID: ItemID = this.equippedCyberwareItemIDs[i];
			let cyberwareType: CName = TweakDBInterface.GetCName(ItemID.GetTDBID(itemID) + t".cyberwareType", n"None");
			if NotEquals(cyberwareType, n"None") {
        		let quality: gamedataQuality = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(itemID)).QualityHandle().Type();
				
				if Equals(cyberwareType, n"IronLungs") {
					switch quality {
						case gamedataQuality.Rare:
							this.cyberwareNicotineEffectDurationOverride = 210.0;  // 30% bonus
							break;
						case gamedataQuality.RarePlus:
							this.cyberwareNicotineEffectDurationOverride = 180.0;  // 40% bonus
							break;
						case gamedataQuality.Epic:
							this.cyberwareNicotineEffectDurationOverride = 150.0;  // 50% bonus
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareNicotineEffectDurationOverride = 120.0;  // 60% bonus
							break;
						case gamedataQuality.Legendary:
							this.cyberwareNicotineEffectDurationOverride = 90.0;   // 70% bonus
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareNicotineEffectDurationOverride = 60.0;   // 80% bonus
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareNicotineEffectDurationOverride = 30.0;   // 90% bonus
							break;
					}

				} else if Equals(cyberwareType, n"EndorphinRegulator") {
					switch quality {
						case gamedataQuality.Epic:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.40; // 60% bonus
							this.cyberwareAlcoholNumbedRequiredStacksOverride = 3u;
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.30; // 70% bonus
							this.cyberwareAlcoholNumbedRequiredStacksOverride = 3u;
							break;
						case gamedataQuality.Legendary:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.20; // 80% bonus
							this.cyberwareAlcoholNumbedRequiredStacksOverride = 2u;
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.10; // 90% bonus
							this.cyberwareAlcoholNumbedRequiredStacksOverride = 2u;
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareNerveLossFromNarcoticsBonusMult = 0.0; // 100% bonus
							this.cyberwareAlcoholNumbedRequiredStacksOverride = 2u;
							break;
					}

				} else if Equals(cyberwareType, n"SecondHeart") {
					this.cyberwareHasSecondHeart = true;
				}
			}

			i += 1;
		}

		this.NicotineAddictionSystem.SetNicotineAddictionBackoffDurations();

		DFLog(this.debugEnabled, this, "UpdateCyberwareBonuses Result:");
		DFLog(this.debugEnabled, this, "    cyberwareNerveLossFromNarcoticsBonusMult = " + ToString(this.cyberwareNerveLossFromNarcoticsBonusMult));
		DFLog(this.debugEnabled, this, "    cyberwareHasSecondHeart = " + ToString(this.cyberwareHasSecondHeart));
		DFLog(this.debugEnabled, this, "    cyberwareNicotineEffectDurationOverride = " + ToString(this.cyberwareNicotineEffectDurationOverride));
		DFLog(this.debugEnabled, this, "    cyberwareAlcoholNumbedRequiredStacksOverride = " + ToString(this.cyberwareAlcoholNumbedRequiredStacksOverride));
	}

    public final func GetHasSecondHeart() -> Bool {
        return this.cyberwareHasSecondHeart;
    }

    public final func GetNicotineEffectDurationOverride() -> Float {
        return this.cyberwareNicotineEffectDurationOverride;
    }
	
    public final func GetNerveLossFromNarcoticsBonusMult() -> Float {
        return this.cyberwareNerveLossFromNarcoticsBonusMult;
    }

    public final func GetSecondHeartNerveRestoreAmount() -> Float {
        return this.cyberwareSecondHeartNerveRestoreAmount;
    }

	public final func GetAlcoholNumbedRequiredStacksOverride() -> Uint32 {
		return this.cyberwareAlcoholNumbedRequiredStacksOverride;
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