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
		//DFProfile();
		return DFCyberwareService.Get();
	}
}

public final class DFCyberwareService extends DFSystem {
	private let StatsSystem: ref<StatsSystem>;
	private let TransactionSystem: ref<TransactionSystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;

	private let equipmentSystemPlayerData: ref<EquipmentSystemPlayerData>;
	private let cyberwareEquipmentAreas: array<gamedataEquipmentArea>;
	private let equippedCyberwareItemIDs: array<ItemID>;

    private let cyberwareHasSecondHeart: Bool = false;
    private let cyberwareAlcoholPainTolerantRequiredStacksOverride: Uint32 = 0u;
    private let cyberwareNicotineEffectDurationOverride: Float = 0.0;
	private let cyberwareNerveCostWhenHitBonusMult: Float = 1.0;
	private let cyberwareNarcoticsEffectDurationOverride: Float = 300.0;
	private let cyberwareSecondHeartNerveRestoreAmount: Float = 30.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFCyberwareService> {
		//DFProfile();
		let instance: ref<DFCyberwareService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFCyberwareService>()) as DFCyberwareService;
		return instance;
	}

	public final static func Get() -> ref<DFCyberwareService> {
		//DFProfile();
		return DFCyberwareService.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	private final func RegisterListeners() -> Void {}
	private final func UnregisterListeners() -> Void {}
	private final func RegisterAllRequiredDelayCallbacks() -> Void {}
	public final func UnregisterAllDelayCallbacks() -> Void {}
	public final func OnTimeSkipStart() -> Void {}
	public final func OnTimeSkipCancelled() -> Void {}
	public final func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}
	private final func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	public final func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		//DFProfile();
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	public final func DoPostSuspendActions() -> Void {
		//DFProfile();
		this.SetDefaultBonusState();
	}

	public final func DoPostResumeActions() -> Void {
		//DFProfile();
		this.UpdateEquippedCyberwareAndBonuses();
	}
	
	private final func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public final func GetSystems() -> Void {
		//DFProfile();
		let gameInstance = GetGameInstance();
		this.StatsSystem = GameInstance.GetStatsSystem(gameInstance);
		this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
	}

	public final func SetupData() -> Void {
		//DFProfile();
		this.equipmentSystemPlayerData = EquipmentSystem.GetData(this.player);
		this.cyberwareEquipmentAreas = this.equipmentSystemPlayerData.GetAllCyberwareEquipmentAreas();
	}

	public final func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		this.UpdateEquippedCyberwareAndBonuses();
	}

	//
	//	System-Specific Methods
	private final func SetDefaultBonusState() -> Void {
		//DFProfile();
		this.cyberwareHasSecondHeart = false;
		this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 0u;
		this.cyberwareNicotineEffectDurationOverride = 0.0;
		this.cyberwareNarcoticsEffectDurationOverride = 300.0;
		this.cyberwareSecondHeartNerveRestoreAmount = 30.0;
	}

    public final func UpdateEquippedCyberwareAndBonuses() -> Void {
		//DFProfile();
		this.UpdateEquippedCyberwareItemIDs(this.equippedCyberwareItemIDs);
		this.UpdateCyberwareBonuses();
	}

    private final func UpdateEquippedCyberwareItemIDs(out itemIDs: array<ItemID>) -> Void {
		//DFProfile();
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
		//DFProfile();
		// Reset data.
		this.cyberwareNarcoticsEffectDurationOverride = 300.0;
        this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 0u;
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
							this.cyberwareNarcoticsEffectDurationOverride = 360.0; // 20% bonus
							this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 3u;
							break;
						case gamedataQuality.EpicPlus:
							this.cyberwareNarcoticsEffectDurationOverride = 420.0; // 40% bonus
							this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 3u;
							break;
						case gamedataQuality.Legendary:
							this.cyberwareNarcoticsEffectDurationOverride = 480.0; // 60% bonus
							this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 2u;
							break;
						case gamedataQuality.LegendaryPlus:
							this.cyberwareNarcoticsEffectDurationOverride = 540.0; // 80% bonus
							this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 2u;
							break;
						case gamedataQuality.LegendaryPlusPlus:
							this.cyberwareNarcoticsEffectDurationOverride = 600.0; // 100% bonus
							this.cyberwareAlcoholPainTolerantRequiredStacksOverride = 2u;
							break;
					}

				} else if Equals(cyberwareType, n"SecondHeart") {
					this.cyberwareHasSecondHeart = true;
				}
			}

			i += 1;
		}

		this.NicotineAddictionSystem.SetNicotineAddictionBackoffDurations();

		DFLog(this, "UpdateCyberwareBonuses Result:");
		DFLog(this, "    cyberwareNarcoticsEffectDurationOverride = " + ToString(this.cyberwareNarcoticsEffectDurationOverride));
		DFLog(this, "    cyberwareHasSecondHeart = " + ToString(this.cyberwareHasSecondHeart));
		DFLog(this, "    cyberwareNicotineEffectDurationOverride = " + ToString(this.cyberwareNicotineEffectDurationOverride));
		DFLog(this, "    cyberwareAlcoholPainTolerantRequiredStacksOverride = " + ToString(this.cyberwareAlcoholPainTolerantRequiredStacksOverride));
	}

    public final func GetHasSecondHeart() -> Bool {
		//DFProfile();
        return this.cyberwareHasSecondHeart;
    }

    public final func GetNicotineEffectDurationOverride() -> Float {
		//DFProfile();
        return this.cyberwareNicotineEffectDurationOverride;
    }
	
    public final func GetNarcoticsEffectDurationOverride() -> Float {
		//DFProfile();
        return this.cyberwareNarcoticsEffectDurationOverride;
    }

    public final func GetSecondHeartNerveRestoreAmount() -> Float {
		//DFProfile();
        return this.cyberwareSecondHeartNerveRestoreAmount;
    }

	public final func GetAlcoholPainTolerantRequiredStacksOverride() -> Uint32 {
		//DFProfile();
		return this.cyberwareAlcoholPainTolerantRequiredStacksOverride;
	}

	public final func GetPointsOfCyberwareCapacityAllocated() -> Float {
		//DFProfile();
		return this.StatsSystem.GetStatValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatType.HumanityAllocated);
	}

	public final func GetPointsOfCyberwareCapacityExceeded() -> Float {
		//DFProfile();
		return this.StatsSystem.GetStatValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatType.HumanityOverallocated);
	}
}

//
//	Base Game Methods
//

//	RipperDocGameController - Update equipped Cyberware bonuses after leaving the Ripperdoc vendor screen.
//
@wrapMethod(RipperDocGameController)
protected cb func OnBeforeLeaveScenario(userData: ref<IScriptable>) -> Bool {
	//DFProfile();
	let value: Bool = wrappedMethod(userData);

	let CyberwareSystem: ref<DFCyberwareService> = DFCyberwareService.Get();
	CyberwareSystem.UpdateEquippedCyberwareAndBonuses();

	return value;
}