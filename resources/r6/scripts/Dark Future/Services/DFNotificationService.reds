// -----------------------------------------------------------------------------
// DFNotificationService
// -----------------------------------------------------------------------------
//
// - A service that handles the playback of SFX, VFX, and message-based Notifications.
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.IsCoinFlipSuccessful
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.UI.{
	DFHUDBarType,
	DFConditionType
}
import DarkFuture.Conditions.{
	DFInjuryConditionSystem,
	DFHumanityLossConditionSystem
	//DFBiocorruptionConditionSystem
}

/*
    General guidelines for notifications to help ensure good UX:

      * Audio cues *should not* play simultaneously, as they are often "grunts" in the player's voice. 
	      * The highest-priority cue should win (random if tie).

      * VFX can play simultaneously; most VFX seem to stack well with each other.
          * Some looping VFX require a callback to stop them.

      * HUD UI display (bar display, bar pulses, etc) can play simultaneously.

	  * Warning messages can only display one at a time.
          * Warning messages are *distracting and interruptive*. Only use these when it is actually important.
          * When multiple messages of the same context try to display at around the same time, we should display
            a "combined" version instead to cut down on the amount of message spam.
		  * In general, SFX, VFX, and UI HUD displays are more immersive and less distracting.
*/

public enum DFMessageContext {
	None = 0,
    Need = 1,
	CriticalNeed = 2,
    AlcoholAddiction = 3,
    NicotineAddiction = 4,
    NarcoticAddiction = 5,
	InjuryCondition = 6,
	HumanityLossCondition = 7,
	Cyberpsychosis = 8
	//BiocorruptionCondition = 9
}

public struct DFAudioCue {
    public let audio: CName;
    public let priority: Int32;
}

public struct DFVisualEffect {
    public let visualEffect: CName;
    public let stopCallback: ref<DFNotificationCallback>;
}

public struct DFUIDisplay {
	public let bar: DFHUDBarType;
	public let pulse: Bool;
	public let forceBright: Bool;
	public let ignoreSceneTier: Bool;
	public let showLock: Bool;
}

public struct DFMessage {
	public let key: CName;
	public let type: SimpleMessageType;
    public let context: DFMessageContext;
    public let combinedContextKey: CName;
    public let useCombinedContextKey: Bool;
	public let allowPlaybackInCombat: Bool;
	public let passKeyAsString: Bool;
	public let duration: Float;
}

public struct DFNotification {
    public let sfx: DFAudioCue;
    public let vfx: DFVisualEffect;
	public let ui: DFUIDisplay;
	public let message: DFMessage;
	public let progression: DFProgressionNotification;
	public let callback: ref<DFNotificationCallback>;
	public let audioSceneFact: DFFactNameValue;
    public let allowPlaybackInCombat: Bool;
	public let allowLimitedGameplay: Bool;
	public let preventVFXIfIncompatibleVFXApplied: Bool;
}

public struct DFProgressionNotification {
	public let value: Int32;
	public let remainingPointsToLevelUp: Int32;
	public let barDelta: Int32;
	public let actualDelta: Int32;
	public let titleKey: CName;
	public let type: gamedataProficiencyType;
	public let currentLevel: Int32;
	public let isLevelMaxed: Bool;
}

public class DFProgressionViewData extends ProgressionViewData {
	public let actualDelta: Int32;
}

public struct DFFactNameValue {
	public let name: CName;
	public let value: Int32;
}

public struct DFNotificationPlaybackSet {
	public let sfxToPlay: DFAudioCue;
    public let vfxToPlay: array<DFVisualEffect>;
	public let uiToShow: array<DFUIDisplay>;
	public let messagesToShow: array<DFMessage>;
	public let progressionsToShow: DFProgressionNotificationPlaybackSet;
	public let factsToSet: array<DFFactNameValue>;
	public let callbacks: array<ref<DFNotificationCallback>>;
}

public struct DFProgressionNotificationPlaybackSet {
	public let injury: DFProgressionNotification;
	public let humanityLoss: DFProgressionNotification;
	//public let biocorruption: DFProgressionNotification;
}

public struct DFTutorial {
	public let title: String;
	public let message: String;
	public let iconID: TweakDBID;
	public let video: ResourceAsyncRef;
	public let videoType: VideoType;
}

public final class DFNotificationCallback extends IScriptable {
    // To use, extend this class and provide an implementation for Callback().
	public func Callback() -> Void {};
}

public class ProcessOutOfCombatNotificationQueueDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;
	public let allowLimitedGameplay: Bool = false;

	public static func Create(NotificationService: wref<DFNotificationService>, allowLimitedGameplay: Bool) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ProcessOutOfCombatNotificationQueueDelayCallback> = new ProcessOutOfCombatNotificationQueueDelayCallback();
		self.NotificationService = NotificationService;
		self.allowLimitedGameplay = allowLimitedGameplay;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.NotificationService.processOutOfCombatNotificationQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.NotificationService.OnProcessOutOfCombatNotificationQueue(this.allowLimitedGameplay);
	}
}

public class ProcessInCombatNotificationQueueDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ProcessInCombatNotificationQueueDelayCallback> = new ProcessInCombatNotificationQueueDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.NotificationService.processInCombatNotificationQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.NotificationService.OnProcessInCombatNotificationQueue();
	}
}

public class DisplayNextMessageDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<DisplayNextMessageDelayCallback> = new DisplayNextMessageDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.NotificationService.displayNextMessageDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.NotificationService.DisplayQueuedMessages();
	}
}

public class DisplayNextTutorialDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<DisplayNextTutorialDelayCallback> = new DisplayNextTutorialDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.NotificationService.displayNextTutorialDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.NotificationService.OnDisplayNextTutorial();
	}
}

public class DisplayHUDUIEvent extends CallbackSystemEvent {
    private let data: DFUIDisplay;

    public func GetData() -> DFUIDisplay {
		//DFProfile();
        return this.data;
    }

    public static func Create(data: DFUIDisplay) -> ref<DisplayHUDUIEvent> {
		//DFProfile();
        let event = new DisplayHUDUIEvent();
        event.data = data;
        return event;
    }
}

class DFNotificationServiceEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFNotificationService> {
		//DFProfile();
		return DFNotificationService.Get();
	}
}

public final class DFNotificationService extends DFSystem {
	private let BlackboardSystem: ref<BlackboardSystem>;
	private let ItemsNotificationQueue: ref<ItemsNotificationQueue>;
	private let QuestsSystem: ref<QuestsSystem>;
	private let GameStateService: ref<DFGameStateService>;
	private let PlayerStateService: ref<DFPlayerStateService>;
	private let InjuryConditionSystem: ref<DFInjuryConditionSystem>;
	private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;
	//private let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;
	
	private let inCombatNotificationQueue: array<DFNotification>;
    private let outOfCombatNotificationQueue: array<DFNotification>;
	private let messageQueue: array<DFMessage>;
	private let tutorialQueue: array<DFTutorial>;

	public let processInCombatNotificationQueueDelayID: DelayID;
    public let processOutOfCombatNotificationQueueDelayID: DelayID;
    public let displayNextMessageDelayID: DelayID;
	public let displayNextTutorialDelayID: DelayID;

    private let processNotificationQueueDelayInterval: Float = 1.0;
    private let displayNextMessageDelayInterval: Float = 3.0;
	private let displayNextTutorialDelayInterval: Float = 1.0;
    private let displayNextMessageBackoffDelayInterval: Float = 6.0;

	private let queuedProgressionNotifications: array<DFProgressionNotification>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNotificationService> {
		//DFProfile();
		let instance: ref<DFNotificationService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNotificationService>()) as DFNotificationService;
		return instance;
	}

	public final static func Get() -> ref<DFNotificationService> {
		//DFProfile();
		return DFNotificationService.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	public func DoPostResumeActions() -> Void {}
	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	
	public func SetupData() -> Void {
		//DFProfile();
		// Extend the base game gamedataProficiencyType enum.
		let largestConst: Int64 = EnumGetMax(n"gamedataProficiencyType");
		Reflection.GetEnum(n"gamedataProficiencyType").AddConstant(n"DarkFutureHumanityLoss", largestConst + Cast<Int64>(1));
		Reflection.GetEnum(n"gamedataProficiencyType").AddConstant(n"DarkFutureInjury", largestConst + Cast<Int64>(2));
	}

	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterListeners() -> Void {}
	public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

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

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		this.ClearAllNotificationQueues();
	}

	public func GetSystems() -> Void {
		//DFProfile();
		let gameInstance = GetGameInstance();
		this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
		this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
		this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
		this.InjuryConditionSystem = DFInjuryConditionSystem.GetInstance(gameInstance);
		this.HumanityLossConditionSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
	}
	
	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		this.ClearAllNotificationQueues();
	}

	public func UnregisterAllDelayCallbacks() -> Void {
		//DFProfile();
		this.UnregisterProcessOutOfCombatNotificationQueueCallback();
		this.UnregisterProcessInCombatNotificationQueueCallback();
		this.UnregisterDisplayNextMessageCallback();
	}

	//
	//  Notifications
	//
	private final func ClearAllNotificationQueues() -> Void {
		//DFProfile();
		ArrayClear(this.inCombatNotificationQueue);
		ArrayClear(this.outOfCombatNotificationQueue);
		ArrayClear(this.messageQueue);
	}

	public final func ClearOutOfCombatAudioNotifications() -> Void {
		//DFProfile();
		for notification in this.outOfCombatNotificationQueue {
			if NotEquals(notification.sfx.audio, n"") {
				ArrayRemove(this.outOfCombatNotificationQueue, notification);
			}
		}
	}

    public final func QueueNotification(notification: DFNotification, opt forceImmediatePlayback: Bool) -> Void {
		//DFProfile();
		DFLog(this, "QueueNotification notification: " + ToString(notification));
		
		if notification.allowPlaybackInCombat && this.player.IsInCombat() {
			ArrayPush(this.inCombatNotificationQueue, notification);
			if forceImmediatePlayback {
				this.OnProcessInCombatNotificationQueue();
			} else {
				this.RegisterProcessInCombatNotificationQueueCallback();
			}
			
		} else {
			ArrayPush(this.outOfCombatNotificationQueue, notification);
			if forceImmediatePlayback {
				this.OnProcessOutOfCombatNotificationQueue(notification.allowLimitedGameplay);
			} else {
				this.RegisterProcessOutOfCombatNotificationQueueCallback(notification.allowLimitedGameplay);
			}
		}
    }

	public final func OnProcessOutOfCombatNotificationQueue(allowLimitedGameplay: Bool) -> Void {
		//DFProfile();
		if ArraySize(this.outOfCombatNotificationQueue) > 0 {
			let gs: GameState = this.GameStateService.GetGameState(this, false, allowLimitedGameplay);
			let inCombat: Bool = this.player.IsInCombat();

			if Equals(gs, GameState.Valid) {
				if !inCombat {
					this.ProcessNotificationQueue(this.outOfCombatNotificationQueue);
				} else {
					this.RegisterProcessOutOfCombatNotificationQueueCallback(allowLimitedGameplay);
				}

			} else if Equals(gs, GameState.TemporarilyInvalid) {
				this.RegisterProcessOutOfCombatNotificationQueueCallback(allowLimitedGameplay);
			
			} else {
				// We are in an invalid game state, dispose of the notification queue.
				ArrayClear(this.outOfCombatNotificationQueue);
			}
		}
	}

	public final func OnProcessInCombatNotificationQueue() -> Void {
		//DFProfile();
		if ArraySize(this.inCombatNotificationQueue) > 0 {
			let gs: GameState = this.GameStateService.GetGameState(this);

			if Equals(gs, GameState.Valid) {
				this.ProcessNotificationQueue(this.inCombatNotificationQueue);

			} else if Equals(gs, GameState.TemporarilyInvalid) {
				this.RegisterProcessInCombatNotificationQueueCallback();
			
			} else {
				// We are in an invalid game state, dispose of the notification queue.
				ArrayClear(this.inCombatNotificationQueue);
			}
		}
	}

    private final func ProcessNotificationQueue(notificationQueue: script_ref<array<DFNotification>>) -> Void {
		//DFProfile();
		DFLog(this, "ProcessNotificationQueue notificationQueue: " + ToString(notificationQueue));
        /*
            How the notification queue is processed:

            First, go through each queued notification:
				Find any Audio Scene Quest Facts. Store it.
                If no Audio Scene Quest Fact set, find the highest-priority audio cue. Select randomly for ties. Store the winner.
                Find any VFX and store in an array. These can play simultaneously.
                Find any UI display notifications and store in an array. These can play simultaneously.
				Find any messages. Combine any messages that share the same context as appropriate.
				Find any progression notifications. Select the latest one of any type. Discard the rest.
            
            Then:
                Play the audio cue.
                Play all stored VFX.
                Play all UI display notifications.
				Play all of the progression notifications.
				Play all messages.
				Set all quest facts (for use by Quest Phases and Scenes).
        */
        let sfxToPlay: DFAudioCue = DFAudioCue(n"", 9999);
        let vfxToPlay: array<DFVisualEffect>;
		let uiToShow: array<DFUIDisplay>;
		let messagesToShow: array<DFMessage>;
		let progressionsToShow: DFProgressionNotificationPlaybackSet;
		let factsToSet: array<DFFactNameValue>;
		let callbacks: array<ref<DFNotificationCallback>>;

		while ArraySize(Deref(notificationQueue)) > 0 {
			let notification: DFNotification = ArrayPop(Deref(notificationQueue));

			// Audio Scene Fact
			let audioSceneFactSet: Bool = false;
			if NotEquals(notification.audioSceneFact.name, n"") {
				ArrayPush(factsToSet, notification.audioSceneFact);
				audioSceneFactSet = true;
			}
			
			// SFX
			if !audioSceneFactSet && NotEquals(notification.sfx.audio, n"") {
				if notification.sfx.priority < sfxToPlay.priority { // Lower is higher priority
					sfxToPlay = notification.sfx;
				} else if notification.sfx.priority == sfxToPlay.priority {
					if IsCoinFlipSuccessful() {
						sfxToPlay = notification.sfx;
						DFLog(this, "Picking new audio at random or equal priority");
					} else {
						DFLog(this, "Ignoring new audio cue (priorities were equal and random chance failed)");
					}
				} else {
					DFLog(this, "Ignoring new audio cue (priority was less than current queued audio)");
				}
			}

			// VFX
			if NotEquals(notification.vfx.visualEffect, n"") {
				if this.PlayerStateService.HasIncompatibleVFXApplied() && notification.preventVFXIfIncompatibleVFXApplied {
					DFLog(this, "Ignoring new VFX (an incompatible VFX was applied and preventVFXIfIncompatibleVFXApplied = true)");
				} else {
					ArrayPush(vfxToPlay, notification.vfx);
				}
			}

			// UI
			if NotEquals(notification.ui.bar, DFHUDBarType.None) {
				ArrayPush(uiToShow, notification.ui);
			}

			// Progression
			if NotEquals(notification.progression.titleKey, n"") {
				if Equals(EnumInt<gamedataProficiencyType>(notification.progression.type), Cast<Int32>(EnumValueFromName(n"gamedataProficiencyType", n"DarkFutureInjury"))) {
					if notification.progression.currentLevel > progressionsToShow.injury.currentLevel || (notification.progression.currentLevel == progressionsToShow.injury.currentLevel && notification.progression.value > progressionsToShow.injury.value) {
						progressionsToShow.injury = notification.progression;
					}
				} else if Equals(EnumInt<gamedataProficiencyType>(notification.progression.type), Cast<Int32>(EnumValueFromName(n"gamedataProficiencyType", n"DarkFutureHumanityLoss"))) {
					if notification.progression.currentLevel > progressionsToShow.humanityLoss.currentLevel || (notification.progression.currentLevel == progressionsToShow.humanityLoss.currentLevel && notification.progression.value > progressionsToShow.humanityLoss.value) {
						progressionsToShow.humanityLoss = notification.progression;
					}
				/*} else if Equals(EnumInt<gamedataProficiencyType>(notification.progression.type), Cast<Int32>(EnumValueFromName(n"gamedataProficiencyType", n"DarkFutureBiocorruption"))) {
					if notification.progression.currentLevel > progressionsToShow.biocorruption.currentLevel || (notification.progression.currentLevel == progressionsToShow.biocorruption.currentLevel && notification.progression.value > progressionsToShow.biocorruption.value) {
						progressionsToShow.biocorruption = notification.progression;
					}*/
				}
			}

			// Message
			if NotEquals(notification.message.key, n"") {
				let i: Int32 = 0;	
				let duplicateContextFound: Bool = false;
				while i < ArraySize(messagesToShow) && !duplicateContextFound {
					if Equals(messagesToShow[i].context, notification.message.context) {
						// If a combined context key is provided, use it.
						if NotEquals(notification.message.combinedContextKey, n"") {
							messagesToShow[i].useCombinedContextKey = true;
						}
						duplicateContextFound = true;
					}
					i += 1;
				}

				// Add this message to the list if no duplicate contexts were found.
				if !duplicateContextFound {
					ArrayPush(messagesToShow, notification.message);
				}
			}

			// Persistent Effect Callbacks
			if NotEquals(notification.callback, null) {
				ArrayPush(callbacks, notification.callback);
			}
		}

		// Condition special handling - If there are any Progression notifications with the same Condition type as a queued Message, clear them.
		let emptyNotification: DFProgressionNotification;
		for message in messagesToShow {
			if Equals(message.context, DFMessageContext.InjuryCondition) {
				progressionsToShow.injury = emptyNotification;
			} else if Equals(message.context, DFMessageContext.HumanityLossCondition) {
				progressionsToShow.humanityLoss = emptyNotification;
			/*} else if Equals(message.context, DFMessageContext.BiocorruptionCondition) {
				progressionsToShow.biocorruption = emptyNotification;*/
			}
		}

        let nps: DFNotificationPlaybackSet = DFNotificationPlaybackSet(sfxToPlay, vfxToPlay, uiToShow, messagesToShow, progressionsToShow, factsToSet, callbacks);
		this.PlayNotificationPlaybackSet(nps);
    }

	private final func PlayNotificationPlaybackSet(nps: DFNotificationPlaybackSet) -> Void {
		//DFProfile();
		DFLog(this, "PlayNotificationPlaybackSet nps: " + ToString(nps));

		// Play the audio cue.
        if NotEquals(nps.sfxToPlay.audio, n"") {
            let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = nps.sfxToPlay.audio;
			this.player.QueueEvent(evt);
        }

        // Play all VFX.
        for vfx in nps.vfxToPlay {
            GameObjectEffectHelper.StartEffectEvent(this.player, vfx.visualEffect, false, null, true);
            if vfx.stopCallback != null {
                vfx.stopCallback.Callback();
            }
        }

		// Display any requested UI.
        for ui in nps.uiToShow {
			GameInstance.GetCallbackSystem().DispatchEvent(DisplayHUDUIEvent.Create(ui));
		}

		// Display any messages.
		for message in nps.messagesToShow {
			ArrayPush(this.messageQueue, message);
		}
		if ArraySize(this.messageQueue) > 0 {
			this.DisplayQueuedMessages();
		}

		// Display all progression notifications.
		if NotEquals(nps.progressionsToShow.injury.titleKey, n"") {
			this.PushProgressionNotification(nps.progressionsToShow.injury);
			this.InjuryConditionSystem.SetLastDisplayedProgressionNotificationValue(nps.progressionsToShow.injury.value);
		}

		if NotEquals(nps.progressionsToShow.humanityLoss.titleKey, n"") {
			this.PushProgressionNotification(nps.progressionsToShow.humanityLoss);
			this.HumanityLossConditionSystem.SetLastDisplayedProgressionNotificationValue(nps.progressionsToShow.humanityLoss.value);
		}

		/*if NotEquals(nps.progressionsToShow.biocorruption.titleKey, n"") {
			this.PushProgressionNotification(nps.progressionsToShow.biocorruption);
			this.BiocorruptionConditionSystem.SetLastDisplayedProgressionNotificationValue(nps.progressionsToShow.biocorruption.value);
		}*/

		// Set any facts.
		for fact in nps.factsToSet {
			this.QuestsSystem.SetFact(fact.name, fact.value);
		}

		// Make any persistent effect callbacks.
		for pec in nps.callbacks {
			pec.Callback();
		}
	}

	//
	//  Messages
	//
	//	Each message has a Context. If multiple share the same context, set the flag
	//  to use the combined context key instead of storing a new one. This allows
	//  one message to stand in for multiple at once, cutting down on spam.
	//
	//  Warning messages can become annoying, or meaningless noise, very fast. 
	//  They should be used sparingly and combined with contexts whenever possible
	//  in order for them to retain their impact.

	// To reduce complexity, if the player exits combat, and then re-enters it, they may see messages while in combat
	// that were part of an out-of-combat notification set.
    public final func DisplayQueuedMessages() -> Void {
		//DFProfile();
		DFLog(this, "DisplayQueuedMessages - Message Queue: " + ToString(this.messageQueue));
        if ArraySize(this.messageQueue) > 0 {
			let gs: GameState = this.GameStateService.GetGameState(this);

			if Equals(gs, GameState.Valid) {
				let message: DFMessage = ArrayPop(this.messageQueue);
				
				if message.useCombinedContextKey {
					if message.passKeyAsString {
						this.SetMessage(NameToString(message.combinedContextKey), message.type, message.duration);
					} else {
						this.SetMessage(GetLocalizedTextByKey(message.combinedContextKey), message.type, message.duration);
					}
					
				} else {
					if message.passKeyAsString {
						this.SetMessage(NameToString(message.key), message.type, message.duration);
					} else {
						this.SetMessage(GetLocalizedTextByKey(message.key), message.type, message.duration);
					}
				}

				if ArraySize(this.messageQueue) > 0 {
					this.RegisterDisplayNextMessageCallback(this.displayNextMessageBackoffDelayInterval);
				}
			
			} else if Equals(gs, GameState.TemporarilyInvalid) {
				this.RegisterDisplayNextMessageCallback(this.displayNextMessageDelayInterval);

			} else {
				// We are now in an invalid game state, dispose of the message queue.
				ArrayClear(this.messageQueue);
			}
        }
    }

	public final func SetMessage(const message: script_ref<String>, opt msgType: SimpleMessageType, opt duration: Float) -> Void {
		//DFProfile();
		let warningMsg: SimpleScreenMessage;
		warningMsg.isShown = true;
		if duration > 0.0 {
			warningMsg.duration = duration;
		} else {
			warningMsg.duration = 5.00;
		}
		warningMsg.message = Deref(message);
		if NotEquals(msgType, SimpleMessageType.Undefined) {
		warningMsg.type = msgType;
		};
		GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UI_Notifications).SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(warningMsg), true);
	}

	//
	//	Tutorials
	//
	public final func QueueTutorial(tutorial: DFTutorial) -> Void {
		//DFProfile();
		ArrayPush(this.tutorialQueue, tutorial);
		this.RegisterDisplayNextTutorialCallback(this.displayNextTutorialDelayInterval);
	}

    public final func OnDisplayNextTutorial() -> Void {
		//DFProfile();
        if ArraySize(this.tutorialQueue) > 0 {
			if this.GameStateService.IsValidGameState(this) && !this.player.IsInCombat() {
				let tutorial: DFTutorial = ArrayPop(this.tutorialQueue);
				
				let blackboardDef: ref<IBlackboard> = this.BlackboardSystem.Get(GetAllBlackboardDefs().UIGameData);
				let myMargin: inkMargin = inkMargin(0.0, 0.0, 0.0, 0.0);
				let popupSettingsDatum: PopupSettings;
				popupSettingsDatum.closeAtInput = true;
				popupSettingsDatum.pauseGame = true;
				popupSettingsDatum.fullscreen = true;
				popupSettingsDatum.position = PopupPosition.LowerLeft;
				popupSettingsDatum.hideInMenu = true;
				popupSettingsDatum.margin = myMargin;
				

				let tutorialTitle: String = tutorial.title;
				let tutorialMessage: String = tutorial.message;
				let popupDatum: PopupData;
				popupDatum.title = tutorialTitle;
				popupDatum.message = tutorialMessage;
				popupDatum.isModal = true;
				if Equals(ResourceAsyncRef.GetPath(tutorial.video), r"") {
					popupDatum.videoType = VideoType.Unknown;
					popupDatum.iconID = tutorial.iconID;
				} else {
					popupDatum.videoType = tutorial.videoType;
					popupDatum.video = tutorial.video;
				}

				blackboardDef.SetVariant(GetAllBlackboardDefs().UIGameData.Popup_Settings, ToVariant(popupSettingsDatum));
				blackboardDef.SetVariant(GetAllBlackboardDefs().UIGameData.Popup_Data, ToVariant(popupDatum));
				blackboardDef.SignalVariant(GetAllBlackboardDefs().UIGameData.Popup_Data);

				if ArraySize(this.tutorialQueue) > 0 {
					this.RegisterDisplayNextTutorialCallback(this.displayNextTutorialDelayInterval);
				}
			} else {
				this.RegisterDisplayNextTutorialCallback(this.displayNextTutorialDelayInterval);
			}
        }
    }

	//
	//  Progression Notification
	//
	public final func SetItemsNotificationQueue(controller: ref<ItemsNotificationQueue>) -> Void {
		//DFProfile();
		if IsDefined(controller) {
			this.ItemsNotificationQueue = controller;
		}
	}

	public final func PushProgressionNotification(notification: DFProgressionNotification) -> Void {
		//DFProfile();
		if IsDefined(this.ItemsNotificationQueue) {
			DFLog(this, "Progression Notification: " + ToString(notification));
			let colorTheme: CName = notification.actualDelta > 0 ? n"DarkFuture" : n"Skills";
			this.ItemsNotificationQueue.PushDarkFutureProgressNotification(notification.value, notification.remainingPointsToLevelUp, notification.barDelta, notification.actualDelta, colorTheme, GetLocalizedTextByKey(notification.titleKey), notification.type, notification.currentLevel, notification.isLevelMaxed);
		}
	}

	public final func PlayDarkFutureProgressionNotificationSFXNegative() -> Void {
		//DFProfile();
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"vfx_fullscreen_memory_replenish";
        this.player.QueueEvent(evt);
	}

	public final func PlayDarkFutureProgressionNotificationSFXPositive() -> Void {
		//DFProfile();
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"q303_06a_roulette_highlights";
        this.player.QueueEvent(evt);
		// q304_sc_01_briefing_somi_close
		// q304_sc_01_briefing_kurt_photo_01
		// q304_sc_01_briefing_load
		// q304_sc_01_briefing_somi_glitch
		// q001_sc_01_biomon_close
	}

	//
	//  Registration
	//
    private final func RegisterProcessOutOfCombatNotificationQueueCallback(allowLimitedGameplay: Bool) -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessOutOfCombatNotificationQueueDelayCallback.Create(this, allowLimitedGameplay), this.processOutOfCombatNotificationQueueDelayID, this.processNotificationQueueDelayInterval);
	}

	private final func RegisterProcessInCombatNotificationQueueCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessInCombatNotificationQueueDelayCallback.Create(this), this.processInCombatNotificationQueueDelayID, this.processNotificationQueueDelayInterval);
	}

    private final func RegisterDisplayNextMessageCallback(interval: Float) -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DisplayNextMessageDelayCallback.Create(this), this.displayNextMessageDelayID, interval);
	}

	private final func RegisterDisplayNextTutorialCallback(interval: Float) -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DisplayNextTutorialDelayCallback.Create(this), this.displayNextTutorialDelayID, interval);
	}

	//
	//	Deregistration
	//
	private final func UnregisterProcessOutOfCombatNotificationQueueCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.processOutOfCombatNotificationQueueDelayID);
	}

	private final func UnregisterProcessInCombatNotificationQueueCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.processInCombatNotificationQueueDelayID);
	}

    private final func UnregisterDisplayNextMessageCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.displayNextMessageDelayID);
	}
}
