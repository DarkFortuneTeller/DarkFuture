// -----------------------------------------------------------------------------
// DFResourceUtils
// -----------------------------------------------------------------------------
//
// - Patches base game resource files.
//

module DarkFuture.Utils

import DarkFuture.Logging.*

public struct DFSceneOptionIconMap {
    public let locId: Uint64;
    public let icon: TweakDBID;
}


public class DFResourceUtils extends ScriptableService {
    private let sceneOptionIconMaps: array<DFSceneOptionIconMap>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFResourceUtils> {
        //DFProfile();
        let instance: ref<DFResourceUtils> = GameInstance.GetScriptableServiceContainer().GetService(NameOf<DFResourceUtils>()) as DFResourceUtils;
        return instance;
    }

    public final static func Get() -> ref<DFResourceUtils> {
        //DFProfile();
        return DFResourceUtils.GetInstance(GetGameInstance());
    }

    private cb func OnLoad() {
        //DFProfile();

        //this.BuildSceneOptionIconMap();

        // Process Scene Choice Options
        //GameInstance.GetCallbackSystem().RegisterCallback(n"Resource/Load", this, n"OnLoadSceneResource")
        //.AddTarget(ResourceTarget.Type(n"scnSceneResource"));

        // Condition Notification Style
        GameInstance.GetCallbackSystem().RegisterCallback(n"Resource/Load", this, n"ProcessNotificationStyle")
        .AddTarget(ResourceTarget.Path(r"base\\gameplay\\gui\\widgets\\notifications\\notification.inkstyle"));

        // Vending Machines
        //GameInstance.GetCallbackSystem().RegisterCallback(n"Resource/PostLoad", this, n"ProcessVendingMachines")
        //.AddTarget(ResourceTarget.Path(r"base\\gameplay\\devices\\vending_machines\\appearances\\vending_machine_b_cirrus_cage.ent"));

        // Metro Gate Scene (Fast Travel)
        GameInstance.GetCallbackSystem().RegisterCallback(n"Resource/Load", this, n"ProcessMetroGateScene")
        .AddTarget(ResourceTarget.Path(r"base\\open_world\\metro\\ue_metro\\scenes\\ue_metro_02_station_v3.scene"));
    }

    /*protected cb func OnLoadSceneResource(event: ref<ResourceEvent>) -> Void {
        // scnscreenplayChoiceOption.itemId.id -> respective dialogue localization id
        let localizationMap: ref<inkStringMap>;

        let scene: ref<scnSceneResource> = event.GetResource() as scnSceneResource;
        for option in scene.screenplayStore.options {
            localizationMap.Insert(ToString(option.itemId.id), CRUIDToHash(option.locstringId.ruid));
        }

        for node in scene.sceneGraph.graph {
            let choiceNode: ref<scnChoiceNode> = node as scnChoiceNode;

            if IsDefined(choiceNode) {
                let i: Int32 = 0;

                while i < ArraySize(choiceNode.options) {
                    let option = choiceNode.options[i];
                    let dialogueLocalization = localizationMap.Get(ToString(option.screenplayOptionId.id));

                    if Equals(dialogueLocalization, ) {
                        ArrayPush(choiceNode.options[i].iconTagIds, );
                    }

                    i += 1;
                }
            }
        }
    }*/

    private cb func ProcessNotificationStyle(event: ref<ResourceEvent>) -> Void {
        //DFProfile();
        let sr: ref<inkStyleResource> = event.GetResource() as inkStyleResource;
        if IsDefined(sr) {
            DFLogNoSystem(DFSystemlessDebugEnabled(), this, "DFResourceUtils: Injecting inkStyles into notification.inkstyle...");

            let darkFutureStyle: inkStyle;
            darkFutureStyle.state = n"DarkFuture";
            darkFutureStyle.styleID = n"StatsProgress";

            // Construct the style properties.
            let plateBgProp: inkStyleProperty;
            plateBgProp.propertyPath = n"StatsProgress.PlateBg";
            let plateBgPropValueTyped: inkStylePropertyReference;
            plateBgPropValueTyped.referencedPath = n"MainColors.Red";
            plateBgProp.value = plateBgPropValueTyped;

            let plateFgProp: inkStyleProperty;
            plateFgProp.propertyPath = n"StatsProgress.PlateFg";
            let plateFgPropValueTyped: inkStylePropertyReference;
            plateFgPropValueTyped.referencedPath = n"MainColors.Red";
            plateFgProp.value = plateFgPropValueTyped;

            let iconProp: inkStyleProperty;
            iconProp.propertyPath = n"StatsProgress.Icon";
            let iconPropValueTyped: inkStylePropertyReference;
            iconPropValueTyped.referencedPath = n"MainColors.Red";
            iconProp.value = iconPropValueTyped;

            let textInfoProp: inkStyleProperty;
            textInfoProp.propertyPath = n"StatsProgress.TextInfo";
            let textInfoPropValueTyped: inkStylePropertyReference;
            textInfoPropValueTyped.referencedPath = n"MainColors.Red";
            textInfoProp.value = textInfoPropValueTyped;

            let barProp: inkStyleProperty;
            barProp.propertyPath = n"StatsProgress.Bar";
            let barPropValueTyped: inkStylePropertyReference;
            barPropValueTyped.referencedPath = n"MainColors.Red";
            barProp.value = barPropValueTyped;

            let rBracketProp: inkStyleProperty;
            rBracketProp.propertyPath = n"StatsProgress.R_bracket";
            let rBracketPropValueTyped: inkStylePropertyReference;
            rBracketPropValueTyped.referencedPath = n"MainColors.Red";
            rBracketProp.value = rBracketPropValueTyped;

            let textTitleProp: inkStyleProperty;
            textTitleProp.propertyPath = n"StatsProgress.TextTitle";
            let textTitlePropValueTyped: inkStylePropertyReference;
            textTitlePropValueTyped.referencedPath = n"MainColors.Orange";
            textTitleProp.value = textTitlePropValueTyped;

            // Push the properties into the style definition.
            ArrayPush(darkFutureStyle.properties, plateBgProp);
            ArrayPush(darkFutureStyle.properties, plateFgProp);
            ArrayPush(darkFutureStyle.properties, iconProp);
            ArrayPush(darkFutureStyle.properties, textInfoProp);
            ArrayPush(darkFutureStyle.properties, barProp);
            ArrayPush(darkFutureStyle.properties, rBracketProp);
            ArrayPush(darkFutureStyle.properties, textTitleProp);

            // Push the style definition into the inkStyle.
            ArrayPush(sr.styles, darkFutureStyle);

            DFLogNoSystem(DFSystemlessDebugEnabled(), this, "DFResourceUtils: ...done!");
        }
    }

    private cb func ProcessMetroGateScene(event: ref<ResourceEvent>) -> Void {
        //DFProfile();
        let scn: ref<scnSceneResource> = event.GetResource() as scnSceneResource;
        let fastTravelChoiceNode: ref<scnChoiceNode>;
        let fastTravelOption: scnChoiceNodeOption;
        if IsDefined(scn) {
            let graph: array<ref<scnSceneGraphNode>> = scn.sceneGraph.graph;
            for node in graph {
                if node.nodeId.id == 1u {
                    fastTravelChoiceNode = node as scnChoiceNode;
                    break;
                }
            }
        }

        if NotEquals(fastTravelChoiceNode, null) {
            for option in fastTravelChoiceNode.options {
                if Equals(option.caption, n"FT") {
                    fastTravelOption = option;
                    break;
                }
            }
        }

        if Equals(fastTravelOption.caption, n"FT") {
            DFLogNoSystem(DFSystemlessDebugEnabled(), this, "DFResourceUtils: Injecting Fast Travel condition into ue_metro_02_station_v3.scene...");
            let metroFastTravelCondition: ref<questFactsDBCondition> = new questFactsDBCondition();

            let varComparisonConditionType: ref<questVarComparison_ConditionType> = new questVarComparison_ConditionType();
            varComparisonConditionType.comparisonType = EComparisonType.Equal;
            varComparisonConditionType.factName = "df_fact_metro_fast_travel_disabled";
            varComparisonConditionType.value = 0;

            metroFastTravelCondition.type = varComparisonConditionType;

            ArrayPush((fastTravelOption.questCondition as questLogicalCondition).conditions, metroFastTravelCondition);
        }
    }

    private final func BuildSceneOptionIconMap() -> Void {
        //DFProfile();
        this.sceneOptionIconMaps = [
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Sleep_BaseGame"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Sleep_KressStreet"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_EnterRollercoaster"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MQ014MonkFinishPromptA"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MQ014MonkFinishPromptB"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MQ014MonkFinishPromptC"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MQ014MonkFinishPromptD"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Cuddle"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Kiss"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Dance"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Meditate"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Q003TakeInhaler"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Q003MeredithStoutPrompt"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Eat"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Q303SitAndDrink"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Q303PlayBraindance"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_CoffeeDrink"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_DLC6DrinkTea"),
            DFSceneOptionIconMap(3060661460960976900ul, t"ChoiceCaptionParts.DarkFutureInteraction_DLC6HitBall"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_DLC6BurnIncense"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_Smoke"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_TakeDrag"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_ThrowBall"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_SureThrowBall"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MistyTarotFirst"),
            DFSceneOptionIconMap(0ul, t"ChoiceCaptionParts.DarkFutureInteraction_MistyTarotRepeat")
        ];
    }
}

/*class DFSceneOptionProcessor extends IScriptable {
    protected let m_scene: ref<scnSceneResource>;

    // scnscreenplayChoiceOption.itemId.id -> respective dialogue localization id
    protected let m_localizationMap: ref<inkStringMap>;

    protected func MapLocalization() -> Void {
        for option in this.m_scene.screenplayStore.options {
            this.m_localizationMap.Insert(ToString(option.itemId.id), CRUIDToHash(option.locstringId.ruid));
        }
    }

    protected func Process() -> Void {
        for node in this.m_scene.sceneGraph.graph {
            let choiceNode: ref<scnChoiceNode> = node as scnChoiceNode;

            if IsDefined(choiceNode) {
                let i: Int32 = 0;

                while i < ArraySize(choiceNode.options) {
                    let option = choiceNode.options[i];
                    let dialogueLocalization = this.m_localizationMap.Get(ToString(option.screenplayOptionId.id));

                    if Equals(dialogueLocalization, ) { // Hit ball
                        ArrayPush(choiceNode.options[i].iconTagIds, );
                    }

                    i += 1;
                }
            }
        }
    }

    public static final func Process(scene: ref<scnSceneResource>) -> Void {
        let processor: ref<DFSceneOptionProcessor> = new DFSceneOptionProcessor();
        processor.m_scene = scene;
        processor.m_localizationMap = new inkStringMap();

        processor.MapLocalization();
        processor.Process();
    }
}*/

/*
    private cb func ProcessVendingMachines(event: ref<ResourceEvent>) {
    //DFProfile();
        // Update the base game apartment scenes.
        let vendingMachineEntityTemplate: ref<entEntityTemplate> = event.GetResource() as entEntityTemplate;
        FTLog("vending_machine_b_cirrus_cage found!");

        let vendingMachineAsyncResource: ResourceAsyncRef = new ResourceAsyncRef();
        vendingMachineEntityTemplate.includes;
    }

    private final func InjectCustomSceneHookToQuestPhase(questResource: ref<questQuestPhaseResource>, customScenePath: ResRef, startEndNodeNameRoot: String, sceneNodeToInjectId: Uint32) -> Void {
    //DFProfile();
        let questPhaseGraph: array<ref<graphGraphNodeDefinition>> = questResource.graph.nodes;
        let sceneNodeToInject: ref<questSceneNodeDefinition>;

        // Find the existing Scene Node we want to inject ours into.
        for node in questPhaseGraph {
            let nodeAsScene: ref<questSceneNodeDefinition> = node as questSceneNodeDefinition;
            if IsDefined(nodeAsScene) {
                if Equals(nodeAsScene.id, Cast<Uint16>(sceneNodeToInjectId)) {
                    sceneNodeToInject = nodeAsScene;
                    FTLog("Found the scene node to inject");
                }
            }
        }

        if IsDefined(sceneNodeToInject) {
            // Create a new Scene Node.
            let customSceneNode: ref<questSceneNodeDefinition> = new questSceneNodeDefinition();
            customSceneNode.id = Cast<Uint16>(this.AssignNodeId());

            let sceneFileAsyncResource: ResourceAsyncRef = new ResourceAsyncRef();
            ResourceAsyncRef.SetPath(sceneFileAsyncResource, customScenePath);
            customSceneNode.sceneFile = sceneFileAsyncResource;
            customSceneNode.sceneLocation = sceneNodeToInject.sceneLocation;

            // Create the sockets.
            let sceneNodeToInjectSuspendSocket: ref<questSocketDefinition> = new questSocketDefinition();
            let sceneNodeToInjectResumeSocket: ref<questSocketDefinition> = new questSocketDefinition();

            let customSceneNodeInputSocket: ref<questSocketDefinition> = new questSocketDefinition();
            let customSceneNodeOutputSocket: ref<questSocketDefinition> = new questSocketDefinition();

            // Wire up the sockets.
            sceneNodeToInjectSuspendSocket.name = StringToName(startEndNodeNameRoot + "_suspend");
            sceneNodeToInjectSuspendSocket.type = questSocketType.Output;
            let sceneNodeToInjectSuspendSocketConnections: ref<graphGraphConnectionDefinition> = new graphGraphConnectionDefinition();
            sceneNodeToInjectSuspendSocketConnections.destination = customSceneNodeInputSocket;
            sceneNodeToInjectSuspendSocketConnections.source = sceneNodeToInjectSuspendSocket;
            ArrayPush(sceneNodeToInjectSuspendSocket.connections, sceneNodeToInjectSuspendSocketConnections);
            ArrayPush(sceneNodeToInject.sockets, sceneNodeToInjectSuspendSocket);

            sceneNodeToInjectResumeSocket.name = StringToName(startEndNodeNameRoot + "_resume");
            sceneNodeToInjectResumeSocket.type = questSocketType.Input;
            let sceneNodeToInjectResumeSocketConnections: ref<graphGraphConnectionDefinition> = new graphGraphConnectionDefinition();
            sceneNodeToInjectResumeSocketConnections.destination = sceneNodeToInjectResumeSocket;
            sceneNodeToInjectResumeSocketConnections.source = customSceneNodeOutputSocket;
            ArrayPush(sceneNodeToInjectResumeSocket.connections, sceneNodeToInjectResumeSocketConnections);
            ArrayPush(sceneNodeToInject.sockets, sceneNodeToInjectResumeSocket);

            customSceneNodeInputSocket.name = n"In";
            customSceneNodeInputSocket.type = questSocketType.Input;
            let customSceneNodeInputSocketConnections: ref<graphGraphConnectionDefinition> = new graphGraphConnectionDefinition();
            customSceneNodeInputSocketConnections.destination = customSceneNodeInputSocket;
            customSceneNodeInputSocketConnections.source = sceneNodeToInjectSuspendSocket;
            ArrayPush(customSceneNodeInputSocket.connections, customSceneNodeInputSocketConnections);
            ArrayPush(customSceneNode.sockets, customSceneNodeInputSocket);

            customSceneNodeOutputSocket.name = n"Out";
            customSceneNodeOutputSocket.type = questSocketType.Output;
            let customSceneNodeOutputSocketConnections: ref<graphGraphConnectionDefinition> = new graphGraphConnectionDefinition();
            customSceneNodeOutputSocketConnections.destination = sceneNodeToInjectResumeSocket;
            customSceneNodeOutputSocketConnections.source = customSceneNodeOutputSocket;
            ArrayPush(customSceneNodeOutputSocket.connections, customSceneNodeOutputSocketConnections);
            ArrayPush(customSceneNode.sockets, customSceneNodeOutputSocket);

            ArrayPush(questPhaseGraph, customSceneNode);
            FTLog("Wired everything up");
        }
    }

    private final func InjectCustomSceneHookToScene(sceneResource: ref<scnSceneResource>, startEndNodeNameRoot: String, nodeAID: Uint32, nodeBID: Uint32, nodeAOutputSocketOverrideIndex: Int32, nodeBInputSocketOverrideIndex: Int32) -> Void {
    //DFProfile();
        let sceneGraph: array<ref<scnSceneGraphNode>> = sceneResource.sceneGraph.graph;

        let injectionNodeA: ref<scnSceneGraphNode>;
        let injectionNodeB: ref<scnSceneGraphNode>;

        let endNodeId: Uint32 = this.AssignNodeId();
        let startNodeId: Uint32 = this.AssignNodeId();

        for node in sceneGraph {
            if Equals(node.nodeId.id, nodeAID) {
                injectionNodeA = node;
            } else if Equals(node.nodeId.id, nodeBID) {
                injectionNodeB = node;
            }
        }

        if IsDefined(injectionNodeA) {
            // Break the link between Node A and Node B.
            // Create a new End node. Link it to Node A.
            let endNode: ref<scnEndNode> = this.CreateSceneEndNode(endNodeId);
            ArrayPush(sceneGraph, endNode);
            this.AddExitPointToScene(sceneResource, endNode, StringToName(startEndNodeNameRoot + "_suspend"));

            let outputSocket: scnOutputSocket = this.CreateSceneOutputSocket(endNodeId);
            injectionNodeA.outputSockets[nodeAOutputSocketOverrideIndex] = outputSocket;
            FTLog("Set up scene injection node A");
        }

        if IsDefined(injectionNodeB) {
            // Break the link between Node B and Node A.
            // Create a new Start node. Link it to Node B.
            let startNode: ref<scnStartNode> = this.CreateSceneStartNode(startNodeId, nodeBID);
            ArrayPush(sceneGraph, startNode);
            this.AddEntryPointToScene(sceneResource, startNode, StringToName(startEndNodeNameRoot + "_resume"));
            FTLog("Set up scene injection node B");
        }
    }

    private final func CreateSceneStartNode(id: Uint32, destinationId: Uint32) -> ref<scnStartNode> {
    //DFProfile();
        let node: ref<scnStartNode>;

        node.ffStrategy = scnFastForwardStrategy.automatic;

        node.nodeId = new scnNodeId();
        node.nodeId.id = id;

        let inputSocketId: scnInputSocketId = new scnInputSocketId();

        let inputSocketStamp: scnInputSocketStamp = new scnInputSocketStamp();
        inputSocketStamp.name = Cast<Uint16>(0u);
        inputSocketStamp.ordinal = Cast<Uint16>(0u);

        inputSocketId.isockStamp = inputSocketStamp;
        inputSocketId.nodeId = new scnNodeId();
        inputSocketId.nodeId.id = destinationId;

        let outputSocketStamp: scnOutputSocketStamp = new scnOutputSocketStamp();
        outputSocketStamp.name = Cast<Uint16>(0u);
        outputSocketStamp.ordinal = Cast<Uint16>(0u);

        let outputSocket: scnOutputSocket = new scnOutputSocket();
        outputSocket.stamp = outputSocketStamp;
        ArrayPush(outputSocket.destinations, inputSocketId);

        ArrayPush(node.outputSockets, outputSocket);

        return node;
    }

    private final func CreateSceneEndNode(id: Uint32) -> ref<scnEndNode> {
    //DFProfile();
        let node: ref<scnEndNode>;

        node.ffStrategy = scnFastForwardStrategy.automatic;

        node.nodeId = new scnNodeId();
        node.nodeId.id = id;

        let outputSocketStamp: scnOutputSocketStamp = new scnOutputSocketStamp();
        outputSocketStamp.name = Cast<Uint16>(0u);
        outputSocketStamp.ordinal = Cast<Uint16>(0u);

        let outputSocket: scnOutputSocket = new scnOutputSocket();
        outputSocket.stamp = outputSocketStamp;

        ArrayPush(node.outputSockets, outputSocket);

        node.type = scnEndNodeNsType.NonTerminating;

        return node;
    }

    private final func CreateSceneOutputSocket(destinationNodeId: Uint32) -> scnOutputSocket {
    //DFProfile();
        let outputSocket: scnOutputSocket = new scnOutputSocket();

        let outputSocketDestination: scnInputSocketId = new scnInputSocketId();

        let outputSocketDestinationIsockStamp: scnInputSocketStamp = new scnInputSocketStamp();
        outputSocketDestinationIsockStamp.name = Cast<Uint16>(0u);
        outputSocketDestinationIsockStamp.ordinal = Cast<Uint16>(0u);

        outputSocketDestination.isockStamp = outputSocketDestinationIsockStamp;
        outputSocketDestination.nodeId = new scnNodeId();
        outputSocketDestination.nodeId.id = destinationNodeId;

        ArrayPush(outputSocket.destinations, outputSocketDestination);

        outputSocket.stamp = new scnOutputSocketStamp();
        outputSocket.stamp.name = Cast<Uint16>(0u);
        outputSocket.stamp.ordinal = Cast<Uint16>(1u);

        return outputSocket;
    }

    private final func AddEntryPointToScene(sceneResource: ref<scnSceneResource>, startNode: ref<scnStartNode>, entryPointName: CName) -> Void {
    //DFProfile();
        let entryPoint: scnEntryPoint = new scnEntryPoint();
        entryPoint.name = entryPointName;
        entryPoint.nodeId = startNode.nodeId;

        ArrayPush(sceneResource.entryPoints, entryPoint);
    }

    private final func AddExitPointToScene(sceneResource: ref<scnSceneResource>, endNode: ref<scnEndNode>, exitPointName: CName) -> Void {
    //DFProfile();
        let exitPoint: scnExitPoint = new scnExitPoint();
        exitPoint.name = exitPointName;
        exitPoint.nodeId = endNode.nodeId;

        ArrayPush(sceneResource.exitPoints, exitPoint);
    }
}
*/
