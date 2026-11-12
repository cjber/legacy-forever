---@meta

-- The TOC supplies one shared namespace to every chunk; none of these declarations run in game.
---@alias LegacySet table<number, boolean>
---@alias LegacyCategoryKey 'areas'|'taxis'|'dungeons'|'raids'|'legacy'|'reputations'|'quests'
---@alias LegacySurface 'map'|'tracker'
---@alias LegacyRefs number[][]
---@alias LegacyCriteria table<number, LegacyProgress>
---@alias LegacyCriteriaReader fun(achievementID: number): LegacyCriteria?
---@alias LegacyTrackingKey number|string

---@class LegacyData
---@field build string
---@field rewards LegacySet
---@field feeds table<number, number[]>
---@field zones table<number, LegacyEntry[]>
---@field completion table<number, LegacyZone>

---@class LegacyEntry
---@field achievement number
---@field criteria number
---@field kind 'explore'|'instance'|'kill'|'quest'|'reputation'
---@field key? string
---@field x? number
---@field y? number
---@field instance? number
---@field raid? boolean

---@class LegacyProgress
---@field text string
---@field completed boolean
---@field index number
---@field type? number
---@field asset? number
---@field quantity? number
---@field required? number

---@class LegacyObjective
---@field entry LegacyEntry
---@field text string
---@field done boolean? a cleared dungeon or raid entrance, kept only for the map

---@class LegacyGroup
---@field achievement number
---@field challenge number
---@field uiMapID number
---@field objectives LegacyObjective[]

---@class LegacyUnlocated
---@field challenge number
---@field open number

---@class LegacyTrackerLine
---@field text? string the step or challenge name; nil while the client has not loaded it
---@field detail? string
---@field seen string

---@class LegacyTrackedBlock
---@field challenge number
---@field lines LegacyTrackerLine[]
---@field seen table<string, boolean>
---@field whole? boolean

---@class LegacyArea
---@field name string
---@field achievement? number
---@field criteria? number
---@field key? string
---@field hit? number[]
---@field tiles? number[]

-- Generated terrain outlines (Data/Explore.lua): one zone's map rectangle in yards and, per completion
-- area key, the rings around its real ground as flat lists of u, v pairs.
---@class LegacyExploreZone
---@field width number
---@field height number
---@field areas table<string, number[][]>

---@class LegacyExplore
---@field build string
---@field zones table<number, LegacyExploreZone>

---@class LegacyShadingMask
---@field [1] number left coordinate in the 1002 by 668 source canvas
---@field [2] number top coordinate in the 1002 by 668 source canvas
---@field [3] number power-of-two texture width
---@field [4] number power-of-two texture height
---@field [5] string complete addon texture path without extension

---@alias LegacyShadingMasks table<number, table<string, LegacyShadingMask>>

---@class LegacyTaxi
---@field name string
---@field node number
---@field faction string

---@class LegacyReferencedObjective
---@field name string
---@field refs LegacyRefs

---@class LegacyRaid
---@field name string
---@field bosses LegacyReferencedObjective[]

---@class LegacyReputation
---@field name string
---@field faction number
---@field side? string

-- One of a zone's quests: a quest, or mutually exclusive ones counted once. `ids` also holds the
-- quests that close it, so it is done once any of them is turned in.
---@class LegacyQuestItem
---@field name string
---@field ids number[]
---@field uiMapID number

-- QuestieDB's quest data for this character, with Questie's blacklist when it is loaded.
---@class LegacyQuestSource
---@field ids number[]
---@field get fun(questID: number, key: string): any
---@field hidden fun(questID: number): boolean
---@field zone fun(areaID: number): number?
---@field race fun(mask: number): boolean
---@field class fun(mask: number): boolean

---@class LegacyZone
---@field areas LegacyArea[]
---@field taxis LegacyTaxi[]
---@field dungeons LegacyReferencedObjective[]
---@field raids LegacyRaid[]
---@field legacy LegacyReferencedObjective[]
---@field reputations LegacyReputation[]
---@field tileWidth? number
---@field tileHeight? number

---@class LegacySnapshot
---@field explored table<string, boolean>
---@field taxis table<number, boolean>
---@field faction string
---@field criteria LegacyCriteriaReader
---@field reaction fun(factionID: number): number
---@field quests? fun(): LegacyQuestItem[]|false|nil
---@field completed? LegacySet

---@class LegacyCategory
---@field done number
---@field total number
---@field pending number
---@field left string[]
---@field complete boolean

---@class LegacyZoneResult
---@field areas? LegacyCategory
---@field taxis? LegacyCategory
---@field dungeons? LegacyCategory
---@field raids? LegacyCategory
---@field legacy? LegacyCategory
---@field reputations? LegacyCategory
---@field quests? LegacyCategory
---@field done number
---@field total number
---@field pending number
---@field complete boolean
---@field percent? number

---@class LegacyContinentResult
---@field complete number
---@field zones number
---@field percent number

---@class LegacyFlightRecord
---@field known LegacySet
---@field continents LegacySet
---@field observedAt? integer last opened flight-master map timestamp
---@field seen? table<integer, integer> distinct observed nodes, with first observed server timestamps

---@alias LegacySettings table<string, boolean>

---@class LegacyDefaults
---@field showAreas boolean
---@field showEntrances boolean
---@field whatsNew boolean
---@field suggestFamily boolean
---@field zoneCompletion LegacySettings

---@class LegacySavedVariables : ForeverFamilyDB
---@field errors? ForeverCaughtError[] the shared error journal, kept by ForeverCore
---@field log? ForeverDebugLogStore the shared debug log ring, kept by ForeverCore
---@field trackerHost? ForeverTrackerLegacySettings the old tracker table, offered once to ForeverCore
---@field tracked? LegacyTrackingKey[]
---@field zoneCompletion? LegacySettings
---@field flightPaths? table<string, LegacyFlightRecord>
---@field showAreas? boolean
---@field showEntrances? boolean
---@field whatsNew? boolean
---@field suggestFamily? boolean
---@field companions? boolean Before 0.8; Saved migrates it to suggestFamily.
---@field peerStats? table<string, table> Forever Leaderboards' old per-character peer table, dropped once by Saved.
---@field sharedStats? table<string, table> Forever Leaderboards' older shared cache, dropped once by Saved.
---@field lastVersion? string

---@type LegacySavedVariables?
LegacyForeverDB = nil

-- The addon's one public global, set by API.lua.
---@class LegacyForeverGlobal
---@field API LFAPI

---@type LegacyForeverGlobal
LegacyForever = nil

---@class LegacyContinentZone
---@field uiMapID number
---@field name string
---@field groups LegacyGroup[]
---@field count number
---@field x number
---@field y number

---@class LegacyMenuGroup
---@field name string
---@field items LegacyUnlocated[]
---@field subs LegacyMenuGroup[]
---@field subsByName table<string, LegacyMenuGroup>

---@class LegacyAreaObjective
---@field group LegacyGroup
---@field objective LegacyObjective

-- One undiscovered area filled from its real terrain instead of the map-art shading.
---@class LegacyOutlineArea
---@field key string
---@field name string
---@field rings number[][]
---@field outline boolean
---@field objective? LegacyAreaObjective

---@class LegacyOutline
---@field zone LegacyExploreZone
---@field uiMapID number
---@field areas LegacyOutlineArea[]
---@field byKey table<string, LegacyOutlineArea>

-- The pin at an outlined area's place: the point nearest the player, else the first point of its first ring.
---@class LegacyOutlinePin
---@field uiMapID number
---@field area LegacyOutlineArea
---@field x number
---@field y number
---@field yards? number

-- One triangle of an area's terrain fill, three flat u, v pairs: u1, v1, u2, v2, u3, v3.
---@alias LegacyTriangle number[]

-- The objective tracker's own progress bar, created from ObjectiveTrackerProgressBarTemplate.
---@class LegacyZoneProgressBarFill : StatusBar
---@field Label FontString
---@class LegacyZoneProgressBar : Frame
---@field Bar LegacyZoneProgressBarFill
---@field SetPercent fun(self: LegacyZoneProgressBar, percent: number)

-- Completion adds these fields to its tracker header before layout runs.
---@class LegacyTrackerHeader : ObjectiveTrackerModuleHeaderTemplate
---@field Progress LegacyZoneProgressBar

-- The tracker template supplies a frame and the manager assigns its numeric block ID.
---@class LegacyTrackerBlock : Frame, ObjectiveTrackerBlockMixin
---@field id number

---@class LegacyToast : Frame
---@field uiMapID number
---@field Unlocked FontString
---@field Name FontString
---@field Icon { Texture: Texture }

-- The pool proxy's generic object return is specialized to this pin's texture pool.
---@class LegacyTexturePool
---@field Acquire fun(self: LegacyTexturePool): Texture, boolean
---@field ReleaseAll fun(self: LegacyTexturePool)
