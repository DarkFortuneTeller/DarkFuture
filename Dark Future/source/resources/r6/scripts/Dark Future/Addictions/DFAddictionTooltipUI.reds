// -----------------------------------------------------------------------------
// DFAddictionTooltipUI
// -----------------------------------------------------------------------------
//
// - Shows the "Addictive" header on addictive consumable tooltips.
//

module DarkFuture.Addictions

import DarkFuture.System.*

//  ItemTooltipHeaderController - Show the addictive item tooltip header.
//
@addMethod(ItemTooltipHeaderController)
public final func TryToShowAddictiveConsumableHeader(itemData: wref<gameItemData>) -> Void {
    //DFProfile();
    if itemData.HasTag(n"DarkFutureConsumableAddictive") {
        let addictionLabel: String = "";

        if IsSystemEnabledAndRunning(DFNicotineAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveNicotine") {
            addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderNicotine");
        }

        if IsSystemEnabledAndRunning(DFAlcoholAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveAlcohol") {
            addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderAlcohol");
        }

        if IsSystemEnabledAndRunning(DFNarcoticAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveNarcotic") {
            addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderNarcotic");
        }

        if NotEquals(addictionLabel, "") {
            inkWidgetRef.SetVisible(this.m_itemRarityText, true);
            inkWidgetRef.SetState(this.m_itemRarityText, n"Legendary");
            inkTextRef.SetText(this.m_itemRarityText, addictionLabel);
        }
    }
}

// ItemTooltipHeaderController - Displays the "Addictive" header in the Backpack Inventory
//
@wrapMethod(ItemTooltipHeaderController)
public func NEW_Update(data: wref<UIInventoryItem>) -> Void {
    //DFProfile();
    wrappedMethod(data);

    let realItemData: wref<gameItemData> = data.GetRealItemData();
    if !UIItemsHelper.ShouldDisplayTier(data.GetItemType()) || realItemData.HasTag(n"DarkFutureConsumableOverrideTierWithAddictionHeader") {
        // Check to see if we should display an Addiction Warning instead
        this.TryToShowAddictiveConsumableHeader(realItemData);
    }
}
