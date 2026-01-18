// -----------------------------------------------------------------------------
// DFRandomEncounterSystem
// -----------------------------------------------------------------------------
//
// - Service that handles spawning Random Encounters around the player.
//   Supports the Vehicle Sleep System.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Settings.DFSettings
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Utils.DFRunGuard

enum DFNPCSpawnSlot {
    Unassigned = 0,
    Front = 1,
    FrontLeft = 2,
    Left = 3,
    RearLeft = 4,
    Rear = 5,
    RearRight = 6,
    Right = 7,
    FrontRight = 8
}

struct DFGangData {
    let gangName: CName;
    let districtName: String;
}

public final class DFRandomEncounterSystem extends DFSystem {
    private let DynamicEntitySystem: ref<DynamicEntitySystem>;

    private let selectedRandomEncounter: DFGangData;

    private const let maxNPCsThatCanBeSpawned: Int32 = 8;
    private const let minGangNPCsToSpawn: Int32 = 2;
    private const let maxGangNPCsToSpawn: Int32 = 4;

    private const let cityScavengerSpawnChance: Float = 0.15;
    private const let spawnDistance: Float = 5.0;
    private const let spawnAngleOffset_Front: Float = 0.0;
    private const let spawnAngleOffset_FrontLeft: Float = 45.0;
    private const let spawnAngleOffset_Left: Float = 90.0;
    private const let spawnAngleOffset_RearLeft: Float = 135.0;
    private const let spawnAngleOffset_Rear: Float = 180.0;
    private const let spawnAngleOffset_RearRight: Float = 225.0;
    private const let spawnAngleOffset_Right: Float = 270.0;
    private const let spawnAngleOffset_FrontRight: Float = 315.0;

    private let hostileGangs: array<CName>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFRandomEncounterSystem> {
        //DFProfile();
		let instance: ref<DFRandomEncounterSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFRandomEncounterSystem>()) as DFRandomEncounterSystem;
		return instance;
	}

	public final static func Get() -> ref<DFRandomEncounterSystem> {
        //DFProfile();
		return DFRandomEncounterSystem.GetInstance(GetGameInstance());
	}

    // DFSystem Required Methods
    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        return this.Settings.enableRandomEncountersWhenSleepingInVehicles;
    }

    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "enableRandomEncountersWhenSleepingInVehicles";
    }

    public func DoPostSuspendActions() -> Void {}
    public func DoPostResumeActions() -> Void {}

    public func GetSystems() -> Void {
        //DFProfile();
        this.DynamicEntitySystem = GameInstance.GetDynamicEntitySystem();
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    public func SetupData() -> Void {
        //DFProfile();
        this.hostileGangs = [
            n"Animals",
            n"Barghest",
            n"Maelstrom",
            n"Scavengers",
            n"SixthStreet",
            n"TygerClaws",
            n"Valentinos",
            n"Wraiths"
        ];
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
        this.DynamicEntitySystem.RegisterListener(n"DarkFuture.SpawnedNPC", this, n"OnPuppetUpdate");
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    
    private func UnregisterListeners() -> Void {
        this.DynamicEntitySystem.UnregisterListener(n"DarkFuture.SpawnedNPC", this, n"OnPuppetUpdate");
    }
    
    public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    // System-Specific Methods
    private cb func OnPuppetUpdate(event: ref<DynamicEntityEvent>) {
        //DFProfile();
		let type = event.GetEventType();
		let id = event.GetEntityID();

		if Equals(type, DynamicEntityEventType.Spawned) {
			let puppet: ref<NPCPuppet> = this.DynamicEntitySystem.GetEntity(id) as NPCPuppet;
            if puppet.HasTag(n"DarkFuture.SpawnedNPCHostile") {
                StimBroadcasterComponent.SendStimDirectly(this.player, gamedataStimType.CombatHit, puppet);
            }
		}
	}

    public final func SetupRandomEncounterOnSleep() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        let currentDistrictRecord: ref<District_Record> = this.player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord();
        if IsDefined(currentDistrictRecord) {
            let hostileGangData = this.GetHostileDistrictGang(currentDistrictRecord);
            
            let encounterChance: Float = this.GetRandomEncounterChanceForDistrict(hostileGangData);

            let randomChance = RandRangeF(0.0, 1.0);
            DFLog(this, "SetupRandomEncounterOnSleep roll: " + ToString(randomChance) + ", encounterChance: " + ToString(encounterChance));

            if encounterChance >= randomChance {
                this.selectedRandomEncounter = hostileGangData;
            }
        }
    }

    public final func TryToSpawnRandomEncounterAroundPlayer() -> Bool {
        //DFProfile();
        if DFRunGuard(this) { return false; }
        let spawnedEncounter: Bool = false;

        if NotEquals(this.selectedRandomEncounter.gangName, n"") {
            DFLog(this, "Spawn encounter!");

            // Scavengers have a chance to spawn in all areas within the city, even if not rolled.
            if NotEquals(this.selectedRandomEncounter.gangName, n"Scavengers") && NotEquals(this.selectedRandomEncounter.gangName, n"Wraiths") {
                let scavengerChance: Float = RandRangeF(0.0, 1.0);
                if this.cityScavengerSpawnChance >= scavengerChance {
                    DFLog(this, "Randomly selected Scavengers instead of selected gang!");
                    this.selectedRandomEncounter.gangName = n"Scavengers";
                }
            }

            let possiblePuppetsToSpawn: array<TweakDBID> = this.GetCharacterListFromFactionName(this.selectedRandomEncounter.gangName);
            let numToSpawn: Int32 = RandRange(this.minGangNPCsToSpawn, this.maxGangNPCsToSpawn);

            let puppetsToSpawn: array<TweakDBID> = [];
            let i: Int32 = 0;
            while i < numToSpawn {
                let randomPuppetIdx: Int32 = RandRange(0, ArraySize(possiblePuppetsToSpawn) - 1);
                ArrayPush(puppetsToSpawn, possiblePuppetsToSpawn[randomPuppetIdx]);

                i += 1;
            }

            DFLog(this, "Selected puppets: ");
            for puppet in puppetsToSpawn {
                DFLog(this, "    " + TDBID.ToStringDEBUG(puppet));
            }

            this.SpawnPuppets(puppetsToSpawn, true);
            spawnedEncounter = true;
        }

        // Clear the random encounter data.
        this.ClearRandomEncounter();

        return spawnedEncounter;
    }

    public final func ClearRandomEncounter() -> Void {
        //DFProfile();
        this.selectedRandomEncounter = DFGangData(n"", "");
    }

    private final func GetRandomEncounterChanceForDistrict(gangData: DFGangData) -> Float {
        //DFProfile();
        // Badlands
        if Equals(gangData.districtName, "Badlands") || Equals(gangData.districtName, "NorthBadlands") || Equals(gangData.districtName, "SouthBadlands") {
            return this.Settings.randomEncounterChanceBadlandsV2 / 100.0;

        // City Center
        } else if Equals(gangData.districtName, "CityCenter") {
            return this.Settings.randomEncounterChanceCityCenter / 100.0;

        // Other Gang-Controlled Locations    
        } else if ArrayContains(this.hostileGangs, gangData.gangName) {
            return this.Settings.randomEncounterChanceGangDistrict / 100.0;

        // No Gang found
        } else {
            return 0.0;
        }

    }

    private final func GetHostileDistrictGang(districtRecord: wref<District_Record>) -> DFGangData {
        //DFProfile();
        let selectedGangData: DFGangData;

        if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoCombat") && IsDefined(districtRecord) {
            selectedGangData = this.GetHostileDistrictGangRecursive(districtRecord);
            
            // Exceptions
            if Equals(selectedGangData.gangName, n"") {
                if Equals(selectedGangData.districtName, "Badlands") || Equals(selectedGangData.districtName, "NorthBadlands") || Equals(selectedGangData.districtName, "SouthBadlands") {
                    //	If in the Badlands, use the Wraiths gang.
                    selectedGangData.gangName = n"Wraiths";

                } else {
                    // In any other district, use the Scavengers faction if no other faction qualifies.
                    // (This will be the only faction used in City Center.)
                    selectedGangData.gangName = n"Scavengers";
                }
                DFLog(this, "Selected gang: " + NameToString(selectedGangData.gangName) + ", district: " + selectedGangData.districtName);
            }
        }

        return selectedGangData;
    }

	private final func GetHostileDistrictGangRecursive(districtRecord: wref<District_Record>) -> DFGangData {
        //DFProfile();
		// May return nothing if no hostile gang is found.
		let selectedGangData: DFGangData;
		
		let gangs: array<wref<Affiliation_Record>>;
		let districtHostileGangs: array<wref<Affiliation_Record>>;
		
        let districtName: String = districtRecord.EnumName();
        selectedGangData.districtName = districtName;

        if districtRecord.GetGangsCount() > 0 {
            districtRecord.Gangs(gangs);
        }

		if ArraySize(gangs) > 0 {
			// Check if any of the gangs in the list are player-hostile gangs.
			for gang in gangs {
				let gangName: CName = gang.EnumName();
				if ArrayContains(this.hostileGangs, gangName) {
					ArrayPush(districtHostileGangs, gang);
					break;
				}
			}
		}

		if ArraySize(districtHostileGangs) > 0 {
			// Select a gang from the list at random.
			let randomIdx: Int32 = RandRange(0, ArraySize(districtHostileGangs) - 1);
			selectedGangData.gangName = districtHostileGangs[randomIdx].EnumName();
            DFLog(this, "Selected gang: " + NameToString(selectedGangData.gangName) + ", district: " + selectedGangData.districtName);

		} else {
			// We didn't find any hostile gangs in the current district. If there is
			// a parent district, check that one.
            DFLog(this, "No gang found for district: " + selectedGangData.districtName);

			let parent = districtRecord.ParentDistrict();
			if IsDefined(parent) {
				selectedGangData = this.GetHostileDistrictGangRecursive(parent);
			}
		}

		return selectedGangData;
	}

    private final func GetCharacterListFromFactionName(factionName: CName) -> array<TweakDBID> {
        //DFProfile();
        switch factionName {
            case n"Animals":
                return this.GetFactionCharacterList_Animals();
                break;
			case n"Barghest":
                return this.GetFactionCharacterList_Barghest();
                break;
			case n"Maelstrom":
                return this.GetFactionCharacterList_Maelstrom();
                break;
            case n"Scavengers":
                return this.GetFactionCharacterList_Scavengers();
                break;
			case n"SixthStreet":
                return this.GetFactionCharacterList_SixthStreet();
                break;
			case n"TygerClaws":
                return this.GetFactionCharacterList_TygerClaws();
                break;
			case n"Valentinos":
                return this.GetFactionCharacterList_Valentinos();
                break;
            case n"Wraiths":
                return this.GetFactionCharacterList_Wraiths();
                break;
        }

        DFLog(this, "Did not find character list from factionName!");
    }

    private final func GetFactionCharacterList_Animals() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Animals character list.");
        return [
            t"Character.animals_bouncer1_melee1_baton_mb",
            t"Character.animals_bouncer1_ranged1_kenshin_mb",
            t"Character.animals_bouncer1_ranged1_omaha_mb",
            t"Character.animals_bouncer2_ranged2_burya_mb",
            t"Character.animals_grunt1_melee1_baseball_mb",
            t"Character.animals_grunt1_ranged1_nova_mb",
            t"Character.animals_grunt1_ranged1_pulsar_mb",
            t"Character.animals_grunt2_melee2_hammer_mb",
            t"Character.animals_grunt2_melee2_machete_mb",
            t"Character.animals_grunt2_ranged2_overture_mb",
            t"Character.animals_grunt2_ranged2_pulsar_mb"
        ];
    }

    private final func GetFactionCharacterList_Barghest() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Barghest character list.");
        return [
            t"Character.bou_kurtz_grunt1_ranged1_handgun_ma",
            t"Character.bou_kurtz_grunt1_ranged1_handgun_wa",
            t"Character.bou_kurtz_grunt1_ranged1_saratoga_ma",
            t"Character.bou_kurtz_grunt1_ranged1_saratoga_wa",
            t"Character.high_kurtz_grunt1_ranged1_handgun_ma",
            t"Character.high_kurtz_grunt1_ranged1_handgun_wa",
            t"Character.high_kurtz_grunt1_ranged1_saratoga_ma",
            t"Character.high_kurtz_grunt1_ranged1_saratoga_wa",
            t"Character.combat_zone_gate_kurtz_grunt1_ranged1_handgun_ma",
            t"Character.combat_zone_gate_kurtz_grunt1_ranged1_handgun_wa",
            t"Character.combat_zone_gate_kurtz_grunt1_ranged1_saratoga_ma",
            t"Character.combat_zone_gate_kurtz_grunt1_ranged1_saratoga_wa"
        ];
    }

    private final func GetFactionCharacterList_Maelstrom() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Maelstrom character list.");
        return [
            t"Character.maelstrom_grunt1_melee1_knife_ma",
            t"Character.maelstrom_grunt1_melee1_wrench_ma",
            t"Character.maelstrom_grunt1_melee1_wrench_wa",
            t"Character.maelstrom_grunt1_ranged1_copperhead_ma",
            t"Character.maelstrom_grunt1_ranged1_copperhead_wa",
            t"Character.maelstrom_grunt1_ranged1_lexington_ma",
            t"Character.maelstrom_grunt1_ranged1_lexington_wa",
            t"Character.maelstrom_grunt2_melee2_hammer_ma",
            t"Character.maelstrom_grunt2_melee2_hammer_wa",
            t"Character.maelstrom_grunt2_melee2_machete_ma",
            t"Character.maelstrom_grunt2_melee2_machete_wa",
            t"Character.maelstrom_grunt2_ranged2_ajax_ma",
            t"Character.maelstrom_grunt2_ranged2_ajax_wa",
            t"Character.maelstrom_grunt2_ranged2_copperhead_ma"
        ];
    }

    private final func GetFactionCharacterList_SixthStreet() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Sixth Street character list.");
        return [
            t"Character.sixthstreet_hooligan_melee1_ironpipe_ma",
            t"Character.sixthstreet_hooligan_melee1_ironpipe_wa",
            t"Character.sixthstreet_hooligan_melee1_knife_ma",
            t"Character.sixthstreet_hooligan_melee1_knife_wa",
            t"Character.sixthstreet_hooligan_ranged1_nova_ma",
            t"Character.sixthstreet_hooligan_ranged1_nova_wa",
            t"Character.sixthstreet_hooligan_ranged1_saratoga_ma",
            t"Character.sixthstreet_hooligan_ranged1_saratoga_wa",
            t"Character.sixthstreet_menace1_shotgun2_igla_ma",
            t"Character.sixthstreet_menace1_shotgun2_tactician_ma",
            t"Character.sixthstreet_patrol2_melee2_baseball_wa",
            t"Character.sixthstreet_patrol2_melee2_baton_wa",
            t"Character.sixthstreet_patrol2_ranged2_ajax_wa",
            t"Character.sixthstreet_veteran3_ranged2_ajax_ma"
        ];
    }

    private final func GetFactionCharacterList_Scavengers() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Scavengers character list.");
        return [
            t"Character.scavenger_grunt1_melee1_pipewrench_ma",
            t"Character.scavenger_grunt1_melee1_pipewrench_wa",
            t"Character.scavenger_grunt1_melee1_tireiron_ma",
            t"Character.scavenger_grunt1_melee1_tireiron_wa",
            t"Character.scavenger_grunt1_ranged1_nova_ma",
            t"Character.scavenger_grunt1_ranged1_nova_wa",
            t"Character.scavenger_grunt1_ranged1_pulsar_ma",
            t"Character.scavenger_grunt1_ranged1_pulsar_wa",
            t"Character.scavenger_grunt1_ranged1_slaughtomatic_ma",
            t"Character.scavenger_grunt1_ranged1_slaughtomatic_wa",
            t"Character.scavenger_grunt2_melee2_baseball_ma",
            t"Character.scavenger_grunt2_melee2_knife_ma",
            t"Character.scavenger_grunt2_melee2_knife_wa",
            t"Character.scavenger_grunt2_ranged2_copperhead_ma",
            t"Character.scavenger_grunt2_ranged2_copperhead_wa",
            t"Character.scavenger_grunt2_ranged2_pulsar_ma",
            t"Character.scavenger_grunt2_ranged2_pulsar_wa"
        ];
    }

    private final func GetFactionCharacterList_TygerClaws() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Tyger Claws character list.");
        return [
            t"Character.tyger_claws_biker1_melee1_baseball_ma",
            t"Character.tyger_claws_biker1_melee1_baseball_wa",
            t"Character.tyger_claws_biker1_melee1_tireiron_ma",
            t"Character.tyger_claws_biker1_melee1_tireiron_wa",
            t"Character.tyger_claws_biker1_ranged1_nue_ma",
            t"Character.tyger_claws_biker1_ranged1_nue_wa",
            t"Character.tyger_claws_biker1_ranged1_saratoga_ma",
            t"Character.tyger_claws_biker1_ranged1_saratoga_wa",
            t"Character.tyger_claws_biker2_melee2_baseball_ma",
            t"Character.tyger_claws_biker2_melee2_baseball_wa",
            t"Character.tyger_claws_biker2_ranged2_copperhead_ma",
            t"Character.tyger_claws_biker2_ranged2_copperhead_wa",
            t"Character.tyger_claws_biker2_ranged2_shingen_ma",
            t"Character.tyger_claws_biker2_ranged2_shingen_wa",
            t"Character.tyger_claws_biker3_shotgun2_tactician_wa",
            t"Character.tyger_claws_gangster1_melee1_knife_ma",
            t"Character.tyger_claws_gangster1_melee1_knife_wa",
            t"Character.tyger_claws_gangster1_ranged1_copperhead_ma",
            t"Character.tyger_claws_gangster1_ranged1_copperhead_wa",
            t"Character.tyger_claws_gangster1_ranged1_nue_ma",
            t"Character.tyger_claws_gangster1_ranged1_nue_wa",
            t"Character.tyger_claws_gangster2_ranged2_copperhead_ma",
            t"Character.tyger_claws_gangster2_ranged2_copperhead_wa",
            t"Character.tyger_claws_gangster2_ranged2_shingen_ma",
            t"Character.tyger_claws_gangster2_ranged2_shingen_wa",
            t"Character.tyger_claws_gangster2_ranged2_sidewinder_ma",
            t"Character.tyger_claws_gangster2_ranged2_sidewinder_wa",
            t"Character.tyger_claws_gangster3_ranged3_sidewinder_ma"
        ];
    }

    private final func GetFactionCharacterList_Valentinos() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Valentinos character list.");
        return [
            t"Character.valentinos_grunt1_melee1_baseball_ma",
            t"Character.valentinos_grunt1_melee1_baseball_wa",
            t"Character.valentinos_grunt1_melee1_knife_ma",
            t"Character.valentinos_grunt1_melee1_knife_wa",
            t"Character.valentinos_grunt1_ranged1_nova_ma",
            t"Character.valentinos_grunt1_ranged1_nova_wa",
            t"Character.valentinos_grunt1_ranged1_nue_ma",
            t"Character.valentinos_grunt1_ranged1_nue_wa",
            t"Character.valentinos_grunt2_melee2_knife_ma",
            t"Character.valentinos_grunt2_melee2_knife_wa",
            t"Character.valentinos_grunt2_melee2_machete_ma",
            t"Character.valentinos_grunt2_melee2_machete_wa",
            t"Character.valentinos_grunt2_ranged2_ajax_ma",
            t"Character.valentinos_grunt2_ranged2_ajax_wa",
            t"Character.valentinos_grunt2_ranged2_nue_ma",
            t"Character.valentinos_grunt2_ranged2_nue_wa",
            t"Character.valentinos_grunt2_ranged2_overture_ma"
        ];
    }

    private final func GetFactionCharacterList_Wraiths() -> array<TweakDBID> {
        //DFProfile();
        DFLog(this, "Returning Wraiths character list.");
        return [
            t"Character.bls_se_wraiths_grunt1_melee1_ironpipe_wa",
            t"Character.bls_se_wraiths_grunt1_melee1_tireiron_ma",
            t"Character.bls_se_wraiths_grunt1_melee1_tireiron_wa",
            t"Character.bls_se_wraiths_grunt1_ranged1_nova_ma",
            t"Character.bls_se_wraiths_grunt1_ranged1_nova_wa",
            t"Character.bls_se_wraiths_grunt1_ranged1_pulsar_ma",
            t"Character.bls_se_wraiths_grunt1_ranged1_pulsar_wa",
            t"Character.bls_se_wraiths_grunt2_ranged2_copperhead_ma",
            t"Character.bls_se_wraiths_grunt2_ranged2_copperhead_wa",
            t"Character.bls_se_wraiths_grunt2_ranged2_pulsar_ma",
            t"Character.bls_se_wraiths_grunt2_ranged2_pulsar_wa"
        ];
    }

    private final func SpawnPuppets(ids: array<TweakDBID>, spawnHostile: Bool) -> Void {
        //DFProfile();
        let reservedSpawnSlots: array<DFNPCSpawnSlot>;

        for id in ids {
            let npcSpec = new DynamicEntitySpec();
            let reservedSpawnSlot: DFNPCSpawnSlot = this.ReserveSpawnSlot(reservedSpawnSlots);

            npcSpec.recordID = id;
            npcSpec.appearanceName = n"random";
            npcSpec.position = this.GetPositionBySpawnSlot(reservedSpawnSlot);
            npcSpec.orientation = this.GetNeutralOrientation();
            npcSpec.persistState = false;
            npcSpec.persistSpawn = false;
            npcSpec.spawnInView = true;
            npcSpec.active = true;

            ArrayPush(npcSpec.tags, n"DarkFuture.SpawnedNPC");
            if spawnHostile {
                ArrayPush(npcSpec.tags, n"DarkFuture.SpawnedNPCHostile");
            }

            this.DynamicEntitySystem.CreateEntity(npcSpec);
        }
	}

    private func GetDirection(angle: Float) -> Vector4 {
        //DFProfile();
		return Vector4.RotateAxis(this.player.GetWorldForward(), Vector4(0, 0, 1, 0), angle / 180.0 * Pi());
	}

	private final func GetPositionBySpawnSlot(spawnSlot: DFNPCSpawnSlot) -> Vector4 {
        //DFProfile();
		let positionAwayFromPlayer: Vector4 = this.player.GetWorldPosition() + this.GetDirection(this.GetWorldAngleOffsetBySpawnSlot(spawnSlot)) * this.GetSpawnDistance();
		let groundPosition = GameInstance.GetNavigationSystem(GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(positionAwayFromPlayer, 1.0, 5);
		return groundPosition;
	}

    private final func GetWorldAngleOffsetBySpawnSlot(spawnSlot: DFNPCSpawnSlot) -> Float {
        //DFProfile();
        switch spawnSlot {
            case DFNPCSpawnSlot.Front:
                return this.spawnAngleOffset_Front;
                break;
            case DFNPCSpawnSlot.FrontLeft:
                return this.spawnAngleOffset_FrontLeft;
                break;
            case DFNPCSpawnSlot.Left:
                return this.spawnAngleOffset_Left;
                break;
            case DFNPCSpawnSlot.RearLeft:
                return this.spawnAngleOffset_RearLeft;
                break;
            case DFNPCSpawnSlot.Rear:
                return this.spawnAngleOffset_Rear;
                break;
            case DFNPCSpawnSlot.RearRight:
                return this.spawnAngleOffset_RearRight;
                break;
            case DFNPCSpawnSlot.Right:
                return this.spawnAngleOffset_Right;
                break;
            case DFNPCSpawnSlot.FrontRight:
                return this.spawnAngleOffset_FrontRight;
                break;
        }
    }

    private final func GetSpawnDistance() -> Float {
        //DFProfile();
        return this.spawnDistance;
    }

	private final func GetNeutralOrientation() -> Quaternion {
        //DFProfile();
		return EulerAngles.ToQuat(Vector4.ToRotation(this.GetDirection(0.0)));
	}

    private final func ReserveSpawnSlot(out reservedSpawnSlots: array<DFNPCSpawnSlot>) -> DFNPCSpawnSlot {
        //DFProfile();
        // Choose a random spawn slot. Keep trying until a unique spawn slot has been found.
        let assignedSlot: DFNPCSpawnSlot;

        while Equals(assignedSlot, DFNPCSpawnSlot.Unassigned) {
            let randomSlot: DFNPCSpawnSlot = IntEnum<DFNPCSpawnSlot>(RandRange(1, 8));
            if !ArrayContains(reservedSpawnSlots, randomSlot) {
                ArrayPush(reservedSpawnSlots, randomSlot);
                assignedSlot = randomSlot;
            }
        }

        DFLog(this, "ReserveSpawnSlot reservedSpawnSlots: " + ToString(reservedSpawnSlots));
        return assignedSlot;
    }
}
