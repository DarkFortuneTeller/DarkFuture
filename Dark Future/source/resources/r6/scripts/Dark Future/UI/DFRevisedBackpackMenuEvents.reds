// -----------------------------------------------------------------------------
// DFRevisedBackpackMenuEvents
// -----------------------------------------------------------------------------
//
// - Event definition stubs for RevisedBackpack events. If Revised Backpack
//   is installed, use those definitions instead via conditional compilation.
//
public class RevisedCustomEventBackpackOpened extends CallbackSystemEvent {
  let opened: Bool;
}
public class RevisedCustomEventItemHoverOver extends CallbackSystemEvent {
  let data: ref<gameItemData>;
}
public class RevisedCustomEventItemHoverOut extends CallbackSystemEvent {}
public class RevisedCustomEventCategorySelected extends CallbackSystemEvent {
  let categoryId: Int32;
}