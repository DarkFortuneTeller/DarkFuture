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
import DarkFuture.UI.DFHUDBarType

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

enum DFMessageContext {
    Need = 0,
    AlcoholAddiction = 1,
    NicotineAddiction = 2,
    NarcoticAddiction = 3
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
}

public struct DFMessage {
	public let key: CName;
	public let type: SimpleMessageType;
    public let context: DFMessageContext;
    public let combinedContextKey: CName;
    public let useCombinedContextKey: Bool;
	public let ignore: Bool;
}

public struct DFNotification {
    public let sfx: DFAudioCue;
    public let vfx: DFVisualEffect;
	public let ui: DFUIDisplay;
	public let callback: ref<DFNotificationCallback>;
    public let allowPlaybackInCombat: Bool;
}

public struct DFNotificationPlaybackSet {
	public let sfxToPlay: DFAudioCue;
    public let vfxToPlay: array<DFVisualEffect>;
	public let uiToShow: array<DFUIDisplay>;
	public let callbacks: array<ref<DFNotificationCallback>>;
}

public struct DFTutorial {
	public let title: String;
	public let message: String;
	public let iconID: TweakDBID;
}

public final class DFNotificationCallback extends IScriptable {
    // To use, extend this class and provide an implementation for Callback().
	public func Callback() -> Void {};
}

public class ProcessOutOfCombatNotificationQueueDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		let self: ref<ProcessOutOfCombatNotificationQueueDelayCallback> = new ProcessOutOfCombatNotificationQueueDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NotificationService.processOutOfCombatNotificationQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NotificationService.OnProcessOutOfCombatNotificationQueue();
	}
}

public class ProcessInCombatNotificationQueueDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		let self: ref<ProcessInCombatNotificationQueueDelayCallback> = new ProcessInCombatNotificationQueueDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NotificationService.processInCombatNotificationQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NotificationService.OnProcessInCombatNotificationQueue();
	}
}

public class DisplayNextMessageDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		let self: ref<DisplayNextMessageDelayCallback> = new DisplayNextMessageDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NotificationService.displayNextMessageDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NotificationService.OnDisplayNextMessage();
	}
}

public class DisplayNextTutorialDelayCallback extends DFDelayCallback {
	public let NotificationService: wref<DFNotificationService>;

	public static func Create(NotificationService: wref<DFNotificationService>) -> ref<DFDelayCallback> {
		let self: ref<DisplayNextTutorialDelayCallback> = new DisplayNextTutorialDelayCallback();
		self.NotificationService = NotificationService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NotificationService.displayNextTutorialDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NotificationService.OnDisplayNextTutorial();
	}
}

public class DisplayHUDUIEvent extends CallbackSystemEvent {
    private let data: DFUIDisplay;

    public func GetData() -> DFUIDisplay {
        return this.data;
    }

    static func Create(data: DFUIDisplay) -> ref<DisplayHUDUIEvent> {
        let event = new DisplayHUDUIEvent();
        event.data = data;
        return event;
    }
}

class DFNotificationServiceEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFNotificationService> {
		return DFNotificationService.Get();
	}
}

public final class DFNotificationService extends DFSystem {
	private let BlackboardSystem: ref<BlackboardSystem>;
	private let GameStateService: ref<DFGameStateService>;
	
	private let inCombatNotificationQueue: array<DFNotification>;
    private let outOfCombatNotificationQueue: array<DFNotification>;
    private let messageQueue: array<DFMessage>;
	private let tutorialQueue: array<DFTutorial>;

	private let processInCombatNotificationQueueDelayID: DelayID;
    private let processOutOfCombatNotificationQueueDelayID: DelayID;
    private let displayNextMessageDelayID: DelayID;
	private let displayNextTutorialDelayID: DelayID;

    private let processNotificationQueueDelayInterval: Float = 1.0;
    private let displayNextMessageDelayInterval: Float = 3.0;
	private let displayNextTutorialDelayInterval: Float = 1.0;
    private let displayNextMessageBackoffDelayInterval: Float = 6.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNotificationService> {
		let instance: ref<DFNotificationService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Services.DFNotificationService") as DFNotificationService;
		return instance;
	}

	public final static func Get() -> ref<DFNotificationService> {
		return DFNotificationService.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	private func DoPostResumeActions() -> Void {}
	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	private func SetupData() -> Void {}
	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterListeners() -> Void {}
	public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

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

	private func DoPostSuspendActions() -> Void {
		this.ClearAllNotificationQueues();
	}
	
	private func DoStopActions() -> Void {}

	private func GetSystems() -> Void {
		this.BlackboardSystem = GameInstance.GetBlackboardSystem(GetGameInstance());
		this.GameStateService = DFGameStateService.Get();
	}
	
	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		this.ClearAllNotificationQueues();
	}

	private func UnregisterAllDelayCallbacks() -> Void {
		this.UnregisterProcessOutOfCombatNotificationQueueCallback();
		this.UnregisterProcessInCombatNotificationQueueCallback();
		this.UnregisterDisplayNextMessageCallback();
	}

	//
	//  Notifications
	//
	private final func ClearAllNotificationQueues() -> Void {
		ArrayClear(this.inCombatNotificationQueue);
		ArrayClear(this.outOfCombatNotificationQueue);
		ArrayClear(this.messageQueue);
	}

    private final func QueueNotification(notification: DFNotification) -> Void {
		DFLog(this, "QueueNotification sfx = " + ToString(notification.sfx) + ", vfx = " + ToString(notification.vfx) + ", ui = " + ToString(notification.ui) + ", callback = " + ToString(notification.callback) + ", allowPlaybackInCombat = " + ToString(notification.allowPlaybackInCombat));
		
		if notification.allowPlaybackInCombat && this.player.IsInCombat() {
			ArrayPush(this.inCombatNotificationQueue, notification);
			this.RegisterProcessInCombatNotificationQueueCallback();
		} else {
			ArrayPush(this.outOfCombatNotificationQueue, notification);
			this.RegisterProcessOutOfCombatNotificationQueueCallback();
		}
    }

	public final func OnProcessOutOfCombatNotificationQueue() -> Void {
		if ArraySize(this.outOfCombatNotificationQueue) > 0 {
			let gs: GameState = this.GameStateService.GetGameState(this);
			let inCombat: Bool = this.player.IsInCombat();

			if Equals(gs, GameState.Valid) {
				if !inCombat {
					this.ProcessNotificationQueue(this.outOfCombatNotificationQueue);
				} else {
					this.RegisterProcessOutOfCombatNotificationQueueCallback();
				}

			} else if Equals(gs, GameState.TemporarilyInvalid) {
				this.RegisterProcessOutOfCombatNotificationQueueCallback();
			
			} else {
				// We are in an invalid game state, dispose of the notification queue.
				ArrayClear(this.outOfCombatNotificationQueue);
			}
		}
	}

	public final func OnProcessInCombatNotificationQueue() -> Void {
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
		DFLog(this, "ProcessNotificationQueue notificationQueue: " + ToString(notificationQueue));
        /*
            How the notification queue is processed:

            First, go through each queued notification:
                Find the highest-priority audio cue. Select randomly for ties. Store the winner.
                Find any VFX and store in an array. These can play simultaneously.
                Find any UI display notifications and store in an array. These can play simultaneously.
            
            Then:
                Play the audio cue.
                Play all stored VFX.
                Play all UI display notifications.
        */
        let sfxToPlay: DFAudioCue = new DFAudioCue(n"", 9999);
        let vfxToPlay: array<DFVisualEffect>;
		let uiToShow: array<DFUIDisplay>;
		let callbacks: array<ref<DFNotificationCallback>>;

		while ArraySize(Deref(notificationQueue)) > 0 {
			let notification: DFNotification = ArrayPop(Deref(notificationQueue));
			
			// SFX
			if NotEquals(notification.sfx.audio, n"") {
				if notification.sfx.priority < sfxToPlay.priority { // Lower is higher priority
					sfxToPlay = notification.sfx;
				} else if notification.sfx.priority == sfxToPlay.priority {
					if IsCoinFlipSuccessful() {
						sfxToPlay = notification.sfx;
						DFLog(this, "QueueAudioCue picking new audio at random or equal priority");
					} else {
						DFLog(this, "QueueAudioCue ignoring new audio cue (priorities were equal and random chance failed)");
					}
				} else {
					DFLog(this, "QueueAudioCue ignoring new audio cue (priority was less than current queued audio)");
				}
			}

			// VFX
			if NotEquals(notification.vfx.visualEffect, n"") {
				ArrayPush(vfxToPlay, notification.vfx);
			}

			// UI
			if NotEquals(notification.ui.bar, DFHUDBarType.None) {
				ArrayPush(uiToShow, notification.ui);
			}

			// Persistent Effect Callbacks
			if NotEquals(notification.callback, null) {
				ArrayPush(callbacks, notification.callback);
			}
		}

        let nps: DFNotificationPlaybackSet = new DFNotificationPlaybackSet(sfxToPlay, vfxToPlay, uiToShow, callbacks);
		this.PlayNotificationPlaybackSet(nps);
    }

	private final func PlayNotificationPlaybackSet(nps: DFNotificationPlaybackSet) -> Void {
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

		// Make any persistent effect callbacks.
		for pec in nps.callbacks {
			pec.Callback();
		}
	}

	//
	//  Messages
	//
	//  Messages are queued separately from Notifications (SFX, VFX, UI) because they
	//  are used much less frequently and don't necessarily happen in the same moments.
	//
	//	Each message has a Context. If multiple share the same context, set the flag
	//  to use the combined context key instead of storing a new one. This allows
	//  one message to stand in for multiple at once, cutting down on spam.
	//
	//  Warning messages can become annoying, or meaningless noise, very fast. 
	//  They should be used sparingly and combined with contexts whenever possible
	//  in order for them to retain their impact.

	public final func QueueMessage(message: DFMessage) -> Void {
		let i: Int32 = 0;
		if NotEquals(message.combinedContextKey, n"") {
			// If a combined context key is provided, use it.
			let duplicateContextFound: Bool = false;
			while i < ArraySize(this.messageQueue) && !duplicateContextFound {
				if Equals(this.messageQueue[i].context, message.context) {
					this.messageQueue[i].useCombinedContextKey = true;
					duplicateContextFound = true;
				}
				i += 1;
			}

			if !duplicateContextFound {
				ArrayPush(this.messageQueue, message);
			}

		} else {
			// Otherwise, ignore elements from the queue with a duplicate context
			// and use this one instead.
			while i < ArraySize(this.messageQueue) {
				if Equals(this.messageQueue[i].context, message.context) {
					this.messageQueue[i].ignore = true;
				}
				i += 1;
			}

			ArrayPush(this.messageQueue, message);
		}
		
		this.RegisterDisplayNextMessageCallback(this.displayNextMessageDelayInterval);
	}

    public final func OnDisplayNextMessage() -> Void {
        if ArraySize(this.messageQueue) > 0 {
			let gs: GameState = this.GameStateService.GetGameState(this);

			if Equals(gs, GameState.Valid) {
				let message: DFMessage = ArrayPop(this.messageQueue);
				
				if !message.ignore {
					if message.useCombinedContextKey {
						this.player.SetWarningMessage(GetLocalizedTextByKey(message.combinedContextKey), message.type);
					} else {
						this.player.SetWarningMessage(GetLocalizedTextByKey(message.key), message.type);
					}

					if ArraySize(this.messageQueue) > 0 {
						this.RegisterDisplayNextMessageCallback(this.displayNextMessageBackoffDelayInterval);
					}
				} else {
					if ArraySize(this.messageQueue) > 0 {
						// Go to the next message immediately.
						this.RegisterDisplayNextMessageCallback(0.1);
					}
				}
			
			} else if Equals(gs, GameState.TemporarilyInvalid) {
				this.RegisterDisplayNextMessageCallback(this.displayNextMessageDelayInterval);

			} else {
				// We are in an invalid game state, dispose of the message queue.
				ArrayClear(this.messageQueue);
			}
        }
    }

	//
	//	Tutorials
	//
	public final func QueueTutorial(tutorial: DFTutorial) -> Void {
		ArrayPush(this.tutorialQueue, tutorial);
		this.RegisterDisplayNextTutorialCallback(this.displayNextTutorialDelayInterval);
	}

    public final func OnDisplayNextTutorial() -> Void {
        if ArraySize(this.tutorialQueue) > 0 {
			if this.GameStateService.IsValidGameState(this) && !this.player.IsInCombat() {
				let tutorial: DFTutorial = ArrayPop(this.tutorialQueue);
				
				let blackboardDef: ref<IBlackboard> = this.BlackboardSystem.Get(GetAllBlackboardDefs().UIGameData);
				let myMargin: inkMargin = new inkMargin(0.0, 0.0, 0.0, 0.0);
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
				popupDatum.videoType = VideoType.Unknown;
				popupDatum.iconID = tutorial.iconID;

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
	//  Registration
	//
    private final func RegisterProcessOutOfCombatNotificationQueueCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, ProcessOutOfCombatNotificationQueueDelayCallback.Create(this), this.processOutOfCombatNotificationQueueDelayID, this.processNotificationQueueDelayInterval);
	}

	private final func RegisterProcessInCombatNotificationQueueCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, ProcessInCombatNotificationQueueDelayCallback.Create(this), this.processInCombatNotificationQueueDelayID, this.processNotificationQueueDelayInterval);
	}

    private final func RegisterDisplayNextMessageCallback(interval: Float) -> Void {
		RegisterDFDelayCallback(this.DelaySystem, DisplayNextMessageDelayCallback.Create(this), this.displayNextMessageDelayID, interval);
	}

	private final func RegisterDisplayNextTutorialCallback(interval: Float) -> Void {
		RegisterDFDelayCallback(this.DelaySystem, DisplayNextTutorialDelayCallback.Create(this), this.displayNextTutorialDelayID, interval);
	}

	//
	//	Deregistration
	//
	private final func UnregisterProcessOutOfCombatNotificationQueueCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.processOutOfCombatNotificationQueueDelayID);
	}

	private final func UnregisterProcessInCombatNotificationQueueCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.processInCombatNotificationQueueDelayID);
	}

    private final func UnregisterDisplayNextMessageCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.displayNextMessageDelayID);
	}
}