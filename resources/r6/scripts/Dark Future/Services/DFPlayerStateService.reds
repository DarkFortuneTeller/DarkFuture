// -----------------------------------------------------------------------------
// DFPlayerStateService
// -----------------------------------------------------------------------------
//
// - A service that handles general player-related state changes.
//
// - Also handles Fast Travel restrictions.
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.*
import DarkFuture.Utils.{
    RunGuard,
    HoursToGameTimeSeconds
}
import DarkFuture.Main.{ 
    DFAddictionDatum,
    DFMainSystem,
    DFTimeSkipData
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Afflictions.DFTraumaAfflictionSystem

enum DFPlayerDangerFactor {
	Combat = 0,
    Heat = 1,
    BeingRevealed = 2
}

public struct DFPlayerDangerState {
    public let InCombat: Bool;
    public let HasHeat: Bool;
    public let BeingRevealed: Bool;
}

public class PlayerStateServiceOnDamageReceivedEvent extends CallbackSystemEvent {
    let data: ref<gameDamageReceivedEvent>;

    public final func GetData() -> ref<gameDamageReceivedEvent> {
        return this.data;
    }

    static func Create(data: ref<gameDamageReceivedEvent>) -> ref<PlayerStateServiceOnDamageReceivedEvent> {
        let self: ref<PlayerStateServiceOnDamageReceivedEvent> = new PlayerStateServiceOnDamageReceivedEvent();
        self.data = data;
        return self;
    }
}

public class AddictionTreatmentDurationUpdateDelayCallback extends DFDelayCallback {
    public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
		let self: ref<AddictionTreatmentDurationUpdateDelayCallback> = new AddictionTreatmentDurationUpdateDelayCallback();
        self.PlayerStateService = playerStateService;
        return self;
	}

	public func InvalidateDelayID() -> Void {
		this.PlayerStateService.addictionTreatmentDurationUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.PlayerStateService.OnAddictionTreatmentDurationUpdate(this.PlayerStateService.GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds());
	}
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent extends CallbackSystemEvent {
    public let data: Float;

    public func GetData() -> Float {
        return this.data;
    }

    static func Create(data: Float) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent> {
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent extends CallbackSystemEvent {
    public let data: DFAddictionDatum;

    public func GetData() -> DFAddictionDatum {
        return this.data;
    }

    static func Create(data: DFAddictionDatum) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent> {
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionPrimaryEffectAppliedEvent extends CallbackSystemEvent {
    public let effectID: TweakDBID;
    public let effectGameplayTags: array<CName>;

    public func GetEffectID() -> TweakDBID {
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        return this.effectGameplayTags;
    }

    static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectAppliedEvent> {
        let event = new PlayerStateServiceAddictionPrimaryEffectAppliedEvent();
        event.effectID = effectID;
        event.effectGameplayTags = effectGameplayTags;
        return event;
    }
}

public class PlayerStateServiceAddictionPrimaryEffectRemovedEvent extends CallbackSystemEvent {
    public let effectID: TweakDBID;
    public let effectGameplayTags: array<CName>;

    public func GetEffectID() -> TweakDBID {
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        return this.effectGameplayTags;
    }

    static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectRemovedEvent> {
        let event = new PlayerStateServiceAddictionPrimaryEffectRemovedEvent();
        event.effectID = effectID;
        event.effectGameplayTags = effectGameplayTags;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent extends CallbackSystemEvent {
    static func Create() -> ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent> {
        return new PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent();
    }
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();

    if IsSystemEnabledAndRunning(playerStateService) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectTags: array<CName> = evt.staticData.GameplayTags();

        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectApplied(effectID, effectTags);
        } else if Equals(effectID, t"DarkFutureStatusEffect.AddictionTreatmentInhaler") {
            playerStateService.OnAddictionTreatmentDrugConsumed();
        }
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();

    if IsSystemEnabledAndRunning(playerStateService) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectTags: array<CName> = evt.staticData.GameplayTags();

        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectRemoved(effectID, effectTags);
        }
    }

	return wrappedMethod(evt);
}

class DFPlayerStateServiceEventListeners extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFPlayerStateService> {
		return DFPlayerStateService.Get();
	}
}

public final class DFPlayerStateService extends DFSystem {
    private persistent let remainingAddictionTreatmentEffectDurationInGameTimeSeconds: Float = 0.0;
    public persistent let hasShownAddictionTutorial: Bool = false;

    private let PreventionSystem: ref<PreventionSystem>;
    private let MainSystem: ref<DFMainSystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let TraumaSystem: ref<DFTraumaAfflictionSystem>;
    private let GameStateService: ref<DFGameStateService>;

    private let playerHeatStage: Int32 = 0;
    private let playerInDanger: Bool = false;

    private let addictionTreatmentDurationUpdateDelayID: DelayID;
    private let addictionTreatmentDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFPlayerStateService> {
		let instance: ref<DFPlayerStateService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Services.DFPlayerStateService") as DFPlayerStateService;
		return instance;
	}

    public final static func Get() -> ref<DFPlayerStateService> {
        return DFPlayerStateService.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func SetupData() -> Void {}
    private func RegisterListeners() -> Void {}
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func UnregisterListeners() -> Void {}

    private func SetupDebugLogging() -> Void {
        this.debugEnabled = false;
    }

    private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

    private func DoPostResumeActions() -> Void {
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
    }

    private func DoPostSuspendActions() -> Void {
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        this.playerHeatStage = 0;
        this.playerInDanger = false;
        this.UpdateFastTravelState();
    }

    private func DoStopActions() -> Void {}

    private func GetSystems() -> Void {
         let gameInstance = GetGameInstance();
        this.PreventionSystem = this.player.GetPreventionSystem();
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
    }
    
    private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
    }

    private func UnregisterAllDelayCallbacks() -> Void {
        this.UnregisterAddictionTreatmentDurationUpdateCallback();
    }

    public func OnTimeSkipStart() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipStart");

		this.UnregisterAddictionTreatmentDurationUpdateCallback();
    }
    public func OnTimeSkipCancelled() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipCancelled");

		this.RegisterAddictionTreatmentDurationUpdateCallback();
    }
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipFinished");

		this.RegisterAddictionTreatmentDurationUpdateCallback();

		if this.GameStateService.IsValidGameState("DFAddictionSystemBase:OnTimeSkipFinished", true) {
            this.OnAddictionTreatmentDurationUpdateFromTimeSkip(data.targetAddictionValues);
		}
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        if ArrayContains(changedSettings, "fastTravelDisabled") {
            this.UpdateFastTravelState();
        }
    }

    //
    //  System-Specific Methods
    //
    private final func UpdateFastTravelState() -> Void {
        if this.Settings.mainSystemEnabled && this.Settings.fastTravelDisabled {
            FastTravelSystem.AddFastTravelLock(n"DarkFuture", GetGameInstance());
        } else {
            FastTravelSystem.RemoveFastTravelLock(n"DarkFuture", GetGameInstance());
        }
    }

	public final func SetHeatStage(heatStage: Int32) -> Void {
		this.playerHeatStage = heatStage;
	}

    public final func GetPlayerDangerState() -> DFPlayerDangerState {
		let dangerState: DFPlayerDangerState;
        if this.GameStateService.IsValidGameState("GetPlayerDangerState", true) {
            dangerState.InCombat = this.player.IsInCombat();
            dangerState.HasHeat = this.PreventionSystem.GetHeatStageAsInt() > 0u;
            dangerState.BeingRevealed = this.player.IsBeingRevealed();
        }

        return dangerState;
	}

    public final func GetInDangerFromState(dangerState: DFPlayerDangerState) -> Bool {
		return dangerState.InCombat || dangerState.HasHeat || dangerState.BeingRevealed;
	}

    public final func GetInDanger() -> Bool {
        let inDanger: Bool = this.GetInDangerFromState(this.GetPlayerDangerState());
        return inDanger;
    }

    //
    //  Addiction Treatment
    //
    private final func RegisterAddictionTreatmentDurationUpdateCallback() -> Void {
        RegisterDFDelayCallback(this.DelaySystem, AddictionTreatmentDurationUpdateDelayCallback.Create(this), this.addictionTreatmentDurationUpdateDelayID, this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

	private final func UnregisterAddictionTreatmentDurationUpdateCallback() -> Void {
        UnregisterDFDelayCallback(this.DelaySystem, this.addictionTreatmentDurationUpdateDelayID);
	}

    public final func OnAddictionTreatmentDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds > 0.0 {
			this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

			if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
				this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
				this.RemoveAddictionTreatmentEffect();
			}
            DFLog(this.debugEnabled, this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));
		}

        this.DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce);
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public final func OnAddictionTreatmentDurationUpdateFromTimeSkip(addictionData: DFAddictionDatum) -> Void {
        let lastTreatmentDurationValue: Float = this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = addictionData.newAddictionTreatmentDuration;

        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        }

        if lastTreatmentDurationValue > 0.0 && this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.RemoveAddictionTreatmentEffect();
        }

        DFLog(this.debugEnabled, this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));
        this.DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData);
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public final func OnAddictionTreatmentDrugConsumed() -> Void {
		// Clear the Inhaler effect.
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatmentInhaler");

		// Set the duration to 12 hours.
		this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = HoursToGameTimeSeconds(12);

		// Refresh player-facing status effects.
		this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();

        // Update the Nerve target.
        this.NerveSystem.UpdateNerveWithdrawalTarget();
	}

    private final func RemoveAddictionTreatmentEffect() -> Void {
        // Refresh player-facing status effects.
        this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();

        // Update the Nerve target.
        this.NerveSystem.UpdateNerveWithdrawalTarget();
	}

    private final func DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce: Float) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent.Create(gameTimeSecondsToReduce));
    }

    private final func DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData: DFAddictionDatum) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent.Create(addictionData));
    }

    private final func DispatchAddictionTreatmentEffectAppliedOrRemovedEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent.Create());
    }

    public final func GetRemainingAddictionTreatmentDurationInGameTimeSeconds() -> Float {
        return this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
    }

    public final func GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds() -> Float {
        return this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds;
    }

    public final func DispatchAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectAppliedEvent.Create(effectID, effectGameplayTags));
    }

    public final func DispatchAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectRemovedEvent.Create(effectID, effectGameplayTags));
    }
}

//
//	Base Game Methods
//

//  PreventionSystem - Let the Nerve System know when Heat changes. (Counts as being "In Danger".)
//
@wrapMethod(PreventionSystem)
private final func OnHeatChanged(previousHeat: EPreventionHeatStage) -> Void {
	wrappedMethod(previousHeat);

	let PlayerStateService: wref<DFPlayerStateService> = DFPlayerStateService.Get();
	PlayerStateService.SetHeatStage(Cast<Int32>(this.GetHeatStageAsInt()));

	DFNerveSystem.Get().OnDangerStateChanged(PlayerStateService.GetPlayerDangerState());
}

//  PlayerPuppet - Let the Nerve System know when Combat state changes. (Counts as being "In Danger".)
//
@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {
	let result: Bool = wrappedMethod(newState);

	DFNerveSystem.Get().OnDangerStateChanged(DFPlayerStateService.Get().GetPlayerDangerState());

	return result;
}

//  PlayerPuppet - Let the Nerve System know when the player is being traced by a Quickhack that was uploaded undetected. (Counts as being "In Danger".)
//
@wrapMethod(PlayerPuppet)
public final func SetIsBeingRevealed(isBeingRevealed: Bool) -> Void {
	wrappedMethod(isBeingRevealed);

	DFNerveSystem.Get().OnDangerStateChanged(DFPlayerStateService.Get().GetPlayerDangerState());
}

//  GameObject - Let other systems know that a player OnDamageReceived event occurred. (Used by the Injury system.)
//
@wrapMethod(GameObject)
protected final func ProcessDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Void {
	wrappedMethod(evt);

	// If the target was the player, ignoring Pressure Wave attacks (i.e. fall damage)
	if evt.hitEvent.target.IsPlayer() && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.PressureWave) && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.Invalid) {
		GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceOnDamageReceivedEvent.Create(evt));
	}
}

//  FastTravelSystem - Ensure that calls to RemoveAllFastTravelLocks can't forcibly stomp on Dark Future's
//  Disable Fast Travel setting.
//
@wrapMethod(FastTravelSystem)
public final static func RemoveAllFastTravelLocks(game: GameInstance) -> Void {
    // While it seems this function is never called outside of debug contexts, as a failsafe, suppress
    // calls to this function if Dark Future has disabled Fast Travel.
    let settings: ref<DFSettings> = DFSettings.Get();

    if !settings.mainSystemEnabled || !settings.fastTravelDisabled {
        wrappedMethod(game);
    }
}

//  DataTermInkGameController - Continue to show the Location Name on DataTerm screens when Fast Travel
//  is disabled by Dark Future.
//
@wrapMethod(DataTermInkGameController)
private final func UpdatePointText() -> Void {
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.fastTravelDisabled {
        if this.m_point != null {
            this.m_districtText.SetLocalizedTextScript(this.m_point.GetDistrictDisplayName());
            this.m_pointText.SetLocalizedTextScript(this.m_point.GetPointDisplayName());
        }
    } else {
        wrappedMethod();
    }
}

//  FastTravelPointData - Remove Fast Travel points from being shown in the world when the setting is enabled.
//
@wrapMethod(FastTravelPointData)
public final const func ShouldShowMappinInWorld() -> Bool {
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.hideFastTravelMarkers {
        return false;
    } else {
        return wrappedMethod();
    }
}

//  WorldMapTooltipController - Display the word "Location" instead of "Fast Travel" on Fast Travel marker tooltips.
//
@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
    wrappedMethod(data, menu);
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.fastTravelDisabled {
        let fastTravelmappin: ref<FastTravelMappin>;
        let journalManager: ref<JournalManager> = menu.GetJournalManager();
        let player: wref<GameObject> = menu.GetPlayer();

        if Deref(data).controller != null && Deref(data).mappin != null && journalManager != null && player != null {
            fastTravelmappin = Deref(data).mappin as FastTravelMappin;
            if IsDefined(fastTravelmappin) {
                if fastTravelmappin.GetPointData().IsSubway() {
                    inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelMetro"));
                } else {
                    inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelDataTerm"));
                }
            }
        }
    }
}
