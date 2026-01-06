// -----------------------------------------------------------------------------
// DFResourceUtils
// -----------------------------------------------------------------------------
//
// - Patches base game resource files.
//

module DarkFuture.Utils

import DarkFuture.Logging.*


public class DFResourceUtils extends ScriptableService {
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

    private cb func ProcessNotificationStyle(event: ref<ResourceEvent>) -> Void {
        //DFProfile();
        let sr: ref<inkStyleResource> = event.GetResource() as inkStyleResource;
        if IsDefined(sr) {
            DFLogNoSystem(true, this, "DFResourceUtils: Injecting inkStyles into notification.inkstyle...");

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

            DFLogNoSystem(true, this, "DFResourceUtils: ...done!");
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
            DFLogNoSystem(true, this, "DFResourceUtils: Injecting Fast Travel condition into ue_metro_02_station_v3.scene...");
            let metroFastTravelCondition: ref<questFactsDBCondition> = new questFactsDBCondition();
            
            let varComparisonConditionType: ref<questVarComparison_ConditionType> = new questVarComparison_ConditionType();
            varComparisonConditionType.comparisonType = EComparisonType.Equal;
            varComparisonConditionType.factName = "df_fact_metro_fast_travel_disabled";
            varComparisonConditionType.value = 0;

            metroFastTravelCondition.type = varComparisonConditionType;

            ArrayPush((fastTravelOption.questCondition as questLogicalCondition).conditions, metroFastTravelCondition);
        }
    }
}

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