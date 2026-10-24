//
// DELAYED FOR FUTURE UPDATE
//

/*
import DarkFuture.Utils.DFGetPlayer
import DarkFuture.Conditions.DFBiocorruptionConditionSystem

@wrapMethod(ItemTooltipModController)
public final func SetData(data: ref<UIInventoryItemMod>) -> Void {
    let dataAsUIIIMDP: ref<UIInventoryItemModDataPackage> = data as UIInventoryItemModDataPackage;
    if IsDefined(dataAsUIIIMDP) && ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckbox") {
        // "Mod Slot" widget style
        
        inkCompoundRef.RemoveAllChildren(this.m_modAbilitiesContainer);
        inkWidgetRef.SetVisible(this.m_dotIndicator, true);
        inkWidgetRef.SetState(this.m_rarityContainer, n"Common");

        // Set checkbox state
        let label: String;
        let validStatusEffectCondition: Bool;
        if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxWellFed") {
            label = GetLocalizedTextByKey(n"DarkFutureEffectNameWellFed");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"DarkFutureStatusEffect.WellFed");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxSated") {
            label = GetLocalizedTextByKey(n"DarkFutureEffectNameSated");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"DarkFutureStatusEffect.Sated");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxRested") {
            label = GetLocalizedTextByKey(n"Gameplay-StatusEffects-UIData-DisplayName-Rested");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"HousingStatusEffect.Rested");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxAlcohol") {
            label = GetLocalizedTextByKey(n"DarkFutureAlcoholActiveEffectName");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"BaseStatusEffect.Drunk");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxNicotine") {
            label = GetLocalizedTextByKey(n"DarkFutureCigaretteStatusEffectDisplayName");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"DarkFutureStatusEffect.Smoking");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxNarcotic") {
            label = GetLocalizedTextByKey(n"DarkFutureNarcoticStatusEffectDisplayName");
            validStatusEffectCondition = StatusEffectSystem.ObjectHasStatusEffect(DFGetPlayer(), t"DarkFutureStatusEffect.Narcotic");

        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxBiocorruptionZero") {
            label = GetLocalizedTextByKey(n"DarkFutureCombinedEffectBiocorruptionReqNone");
            validStatusEffectCondition = DFBiocorruptionConditionSystem.Get().GetConditionLevel() == 0u;
        
        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectCheckboxBiocorruption") {
            label = GetLocalizedTextByKey(n"DarkFutureCombinedEffectBiocorruptionReq");
            validStatusEffectCondition = DFBiocorruptionConditionSystem.Get().GetConditionLevel() > 0u;
        }

        inkWidgetRef.SetState(this.m_rarityWidget, validStatusEffectCondition ? n"Common" : n"Empty");
        inkWidgetRef.SetState(this.m_dotIndicator, validStatusEffectCondition ? n"Common" : n"Empty");

        this.SpawnController().Setup(label, this.m_isCrafting);
        
    } else if IsDefined(dataAsUIIIMDP) && ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectHeader") {
        // "Attunement" widget style
        inkCompoundRef.RemoveAllChildren(this.m_modAbilitiesContainer);
        this.HideDotIndicator();
        let controller: ref<ItemTooltipModEntryController> = this.SpawnController();

        if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectHeaderWellness") {
            controller.DFCombinedEffectHeaderEntrySetup(GetLocalizedTextByKey(n"DarkFutureCombinedEffectWellnessHeader"), this.m_isCrafting);
        } else if ArrayContains(dataAsUIIIMDP.DataPackage.nameValues, n"DarkFutureDisplayAsCombinedEffectHeaderReckless") {
            controller.DFCombinedEffectHeaderEntrySetup("", this.m_isCrafting);
        }

    } else {
        wrappedMethod(data);
    }
}

@addMethod(ItemTooltipModEntryController)
public final func DFCombinedEffectHeaderEntrySetup(description: String, isCrafting: Bool) -> Void {
    // Set the description.
    inkTextRef.SetText(this.m_modName, description);

    // Set up the header.
    inkTextRef.SetText(this.m_attunementText, GetLocalizedTextByKey(n"DarkFutureCombinedEffectLabel"));
    InkImageUtils.RequestSetImage(this, this.m_attunementIcon, t"UIIcon.DarkFutureCombinedEffectIcon");
    inkWidgetRef.SetMargin(this.m_attunementIcon, 0.0, -2.0, 10.0, 0.0);
    inkWidgetRef.SetSize(this.m_attunementIcon, 48.0, 48.0);
    inkWidgetRef.SetVisible(this.m_attunementContainer, true);

    this.m_settings = new UserSettings();
    this.m_settingsListener = new ItemTooltipModSettingsListener();
    this.m_settingsListener.RegisterController(this);
    this.m_settingsListener.Register(this.m_groupPath);
    this.m_isCrafting = isCrafting;
    this.NewUpdateTooltipSize();
}
*/