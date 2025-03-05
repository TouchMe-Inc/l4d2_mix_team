#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <nativevotes_rework>
#include <colors>

#undef REQUIRE_PLUGIN
#include <left4dhooks>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
    name        = "MixTeam",
    author      = "TouchMe",
    description = "Adds an API for mix in versus mode",
    version     = "build_0010",
    url         = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


/**
 * Libs.
 */
#define LIB_DHOOK               "left4dhooks"

/**
 * Avaible gamemodes.
 */
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"
#define GAMEMODE_SCAVENGE "scavenge"

// Other
#define TRANSLATIONS            "mix_team.phrases"
#define VOTE_TIME               15


/**
 * Teams.
 */
#define TEAM_NONE               0
#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

/**
 * Invalid mix index.
 */
#define INVALID_INDEX           -1

/**
 * Sugar.
 */
#define SetHumanSpec            L4D_SetHumanSpec
#define TakeOverBot             L4D_TakeOverBot


enum struct MixInfo
{
    int minPlayers;
    int abortDelay;
}

enum MixState
{
    MixState_None = 0,
    MixState_Voting,
    MixState_InProgress
}

MixState g_eMixState = MixState_None;

int
    g_iMixIndex = INVALID_INDEX,
    g_iAbortDelay = 0,
    g_iClientTeamBeforePlayerMix[MAXPLAYERS + 1];

bool
    g_bDHookAvailable = false,
    g_bGamemodeAvailable = false,
    g_bRoundIsLive = false,
    g_bClientMixMember[MAXPLAYERS + 1];

ConVar g_cvGameMode = null;

GlobalForward
    g_fwdOnDrawMenuItem = null,
    g_fwdOnDrawVoteTitle = null,
    g_fwdOnChangeMixState = null
;

Handle g_hMixList = null;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    g_bDHookAvailable = LibraryExists(LIB_DHOOK);
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, LIB_DHOOK)) {
        g_bDHookAvailable = true;
    }
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
    if (StrEqual(sName, LIB_DHOOK)) {
        g_bDHookAvailable = false;
    }
}

/**
 * Called before OnPluginStart.
 *
 * @param myself            Handle to the plugin.
 * @param late              Whether or not the plugin was loaded "late" (after map load).
 * @param error             Error message buffer in case load failed.
 * @param err_max           Maximum number of characters for error message buffer.
 * @return                  APLRes_Success | APLRes_SilentFailure.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    // Natives.
    CreateNative("Call_AbortMix", Native_AbortMix);
    CreateNative("Call_FinishMix", Native_FinishMix);
    CreateNative("AddMix", Native_AddMix);
    CreateNative("GetMixState", Native_GetMixState);
    CreateNative("GetMixIndex", Native_GetMixIndex);
    CreateNative("IsMixMember", Native_IsMixMember);
    CreateNative("SetClientTeam", Native_SetClientTeam);

    // Forwards.
    g_fwdOnDrawMenuItem = CreateGlobalForward("OnDrawMenuItem", ET_Hook, Param_Cell, Param_Cell, Param_String, Param_Cell);
    g_fwdOnDrawVoteTitle = CreateGlobalForward("OnDrawVoteTitle", ET_Hook, Param_Cell, Param_Cell, Param_String, Param_Cell);
    g_fwdOnChangeMixState = CreateGlobalForward("OnChangeMixState", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

    // Library.
    RegPluginLibrary("mix_team");

    return APLRes_Success;
}

/**
 * Adds a mix to the system.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return index.
 */
int Native_AddMix(Handle hPlugin, int iParams)
{
    if (iParams < 2) {
        ThrowNativeError(SP_ERROR_NATIVE, "Call native without required params");
    }

    MixInfo mix;

    mix.minPlayers = GetNativeCell(1);

    mix.abortDelay = GetNativeCell(2);

    return PushArrayArray(g_hMixList, mix);
}

/**
 * Returns the status of the mix.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return g_eMixState.
 */
any Native_GetMixState(Handle hPlugin, int iParams) {
    return g_eMixState;
}

/**
 * Returns current Mix Index.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return g_iMixIndex.
 */
int Native_GetMixIndex(Handle hPlugin, int iParams) {
    return g_iMixIndex;
}

/**
 * Forces the mix to stop.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 */
int Native_AbortMix(Handle hPlugin, int iParams)
{
    if (!IsMixStateInProgress()) {
        ThrowNativeError(SP_ERROR_NATIVE, "Call native without mix");
    }

    AbortPlayerMix();
    return 0;
}

/**
 * Forcibly ends the mix.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 */
int Native_FinishMix(Handle hPlugin, int iParams)
{
    if (!IsMixStateInProgress()) {
        ThrowNativeError(SP_ERROR_NATIVE, "Call native without mix");
    }

    FinishPlayerMix();
    return 0;
}

/**
 * Returns whether the player is a member of the mix.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return true if member.
 */
int Native_IsMixMember(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);

    return g_bClientMixMember[iClient];
}

/**
 * Sets a command to a player.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return true if success.
 */
int Native_SetClientTeam(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);
    int iTeam = GetNativeCell(2);

    return SetupClientTeam(iClient, iTeam);
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    // Check Gamemode.
    HookConVarChange(g_cvGameMode = FindConVar("mp_gamemode"), OnGamemodeChanged);
    char sGameMode[16]; GetConVarString(g_cvGameMode, sGameMode, sizeof(sGameMode));
    g_bGamemodeAvailable = IsAvaibleMode(sGameMode);

    // Events.
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);

    // Player Commands.
    RegConsoleCmd("sm_mix", Cmd_RunMix, "Start Team Mix Voting");
    RegAdminCmd("sm_fmix", Cmd_ForceMix, ADMFLAG_BAN, "Run forced Mix");

    // Hook change team <KEY_M>.
    AddCommandListener(Listener_OnPlayerJoinTeam, "jointeam");

    g_hMixList = CreateArray(sizeof(MixInfo));
}

/**
 * Called when a gamemode variable value is changed.
 */
void OnGamemodeChanged(ConVar cv, const char[] szOldGameMode, const char[] szNewGameMode) {
    g_bGamemodeAvailable = IsAvaibleMode(szNewGameMode);
}

/**
  * Called when the map starts loading.
  */
void Event_RoundStart(Event event, const char[] sEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    g_bRoundIsLive = false;
    g_eMixState = MixState_None;
    g_iMixIndex = INVALID_INDEX;
    g_iAbortDelay = 0;

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
    {
        g_bClientMixMember[iPlayer] = false;
    }
}

/**
 * Round start event.
 */
void Event_LeftStartArea(Event event, const char[] sEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    g_bRoundIsLive = true;

    if (IsMixStateInProgress())
    {
        CPrintToChatAll("%t%t", "TAG", "ROUND_STARTED");
        AbortPlayerMix();
    }
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] sEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable || !g_bRoundIsLive) {
        return;
    }

    g_bRoundIsLive = false;
}

/**
 * Sends new players to the observer team.
 * Called before player change his team.
 */
void Event_PlayerTeam(Event event, const char[] sEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable || !IsMixStateInProgress()) {
        return;
    }

    int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

    if (!iClient || IsFakeClient(iClient)) {
        return;
    }

    int iOldTeam = GetEventInt(event, "oldteam");

    DataPack hPack = CreateDataPack();
    WritePackCell(hPack, iClient);
    WritePackCell(hPack, iOldTeam);

    CreateTimer(0.1, Timer_PlayerTeam, hPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
}

/**
 *
 */
Action Timer_PlayerTeam(Handle hTimer, DataPack hPack)
{
    if (!IsMixStateInProgress()) {
        return Plugin_Stop;
    }

    ResetPack(hPack);

    int iClient = ReadPackCell(hPack);
    int iOldTeam = ReadPackCell(hPack);

    if (g_bClientMixMember[iClient])
    {
        /**
         * Player disconnected.
         */
        if (!IsClientInGame(iClient))
        {
            CPrintToChatAll("%t%t", "TAG", "PLAYER_DISCONNECTED");
            AbortPlayerMix();

            return Plugin_Stop;
        }

        /**
         * Player changed team.
         */
        if (g_eMixState == MixState_Voting && IsValidTeam(iOldTeam) && !IsValidTeam(GetClientTeam(iClient)))
        {
            CPrintToChatAll("%t%t", "TAG", "PLAYER_CHANGED_TEAM", iClient);
            AbortPlayerMix();

            return Plugin_Stop;
        }
    }

    /**
     * Player connected.
     */
    else if (IsClientInGame(iClient))  {
        SetupClientTeam(iClient, TEAM_SPECTATOR);
    }

    return Plugin_Stop;
}

/**
 * Blocking a team change if there is a mix of teams now.
 *
 * @param iClient           Client index.
 * @param sCmd              Ignored.
 * @param iArgs             Ignored.
 */
Action Listener_OnPlayerJoinTeam(int iClient, const char[] sCmd, int iArgs)
{
    if (IsMixStateInProgress())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "CANT_CHANGE_TEAM", iClient);
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient           Client index.
 * @param iArgs             Number of parameters.
 */
Action Cmd_RunMix(int iClient, int iArgs)
{
    if (!g_bGamemodeAvailable) {
        return Plugin_Continue;
    }

    if (!IsValidTeam(GetClientTeam(iClient))) {
        return Plugin_Handled;
    }

    if (InSecondHalfOfRound())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "SECOND_HALF_OF_ROUND", iClient);
        return Plugin_Handled;
    }

    if (IsRoundStarted())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_STARTED", iClient);
        return Plugin_Handled;
    }

    if (IsMixStateInProgress())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ALREADY_IN_PROGRESS", iClient);
        return Plugin_Handled;
    }

    if (!GetArraySize(g_hMixList))
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "NOT_FOUND", iClient);
        return Plugin_Handled;
    }

    ShowMixMenu(iClient, .bForce = false);

    return Plugin_Handled;
}

void ShowMixMenu(int iClient, bool bForce)
{
    Menu hMenu = CreateMenu(HandleMenu, MenuAction_Select|MenuAction_End);

    SetMenuTitle(hMenu, "%T", bForce ? "MENU_TITLE_FORCE" : "MENU_TITLE", iClient);

    char szItemData[8], szItemName[64];

    FormatEx(szItemData, sizeof(szItemData), "%d", bForce);
    FormatEx(szItemName, sizeof(szItemName), "%T", "MENU_ABORT", iClient);
    AddMenuItem(hMenu, szItemData, szItemName, IsMixStateInProgress() ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    int iArraySize = GetArraySize(g_hMixList);

    for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
    {
        FormatEx(szItemData, sizeof(szItemData), "%d %d", bForce, iIndex);
        ExecuteForward_OnDrawMenuItem(iIndex, iClient, szItemName, sizeof(szItemName));
        AddMenuItem(hMenu, szItemData, szItemName);
    }

    DisplayMenu(hMenu, iClient, -1);
}

int HandleMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
    switch(hAction)
    {
        case MenuAction_End: CloseHandle(hMenu);

        case MenuAction_Select:
        {
            char szItemData[8], szForce[1];
            GetMenuItem(hMenu, iItem, szItemData, sizeof(szItemData));

            if (iItem == 0)
            {
                bool bForce = view_as<bool>(StringToInt(szForce));

                if (!IsMixStateInProgress())
                {
                    ShowMixMenu(iClient, bForce);
                    return 0;
                }

                if (!g_bClientMixMember[iClient])
                {
                    ShowMixMenu(iClient, bForce);
                    return 0;
                }

                int iEndTime = g_iAbortDelay - GetTime();

                if (iEndTime <= 0 || bForce)
                {
                    CPrintToChatAll("%t%t", "TAG", "ABORT_MIX_SUCCESS", iClient);
                    AbortPlayerMix();
                }

                else {
                    CPrintToChat(iClient, "%T%T", "TAG", iClient, "ABORT_MIX_FAIL", iClient, iEndTime);
                }

                ShowMixMenu(iClient, bForce);

                return 0;
            }

            char szMixIndex[3];
            BreakString(szItemData[BreakString(szItemData, szForce, sizeof(szForce))], szMixIndex, sizeof(szMixIndex));

            bool bForce = view_as<bool>(StringToInt(szForce));
            int iMixIndex = StringToInt(szMixIndex);

            if (!NativeVotes_IsNewVoteAllowed())
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());

                ShowMixMenu(iClient, .bForce = bForce);
                return 0;
            }

            int iMinPlayers = GetMixMinPlayers(iMixIndex);
            int iTotalPlayers = GetPlayerCount();

            if (iTotalPlayers < iMinPlayers)
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "NOT_ENOUGH_PLAYERS", iClient, iMinPlayers);

                ShowMixMenu(iClient, .bForce = bForce);
                return 0;
            }

            g_iMixIndex = iMixIndex;
            SetMixState(MixState_Voting);

            /*
             * Save player team and mark as mix member.
             */
            for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
            {
                g_bClientMixMember[iPlayer] = false;

                if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
                    continue;
                }

                int iTeam = GetClientTeam(iPlayer);

                if (IsValidTeam(iTeam))
                {
                    g_bClientMixMember[iPlayer] = true;
                    g_iClientTeamBeforePlayerMix[iPlayer] = iTeam;
                }
            }

            if (bForce) {
                RunPlayerMix();
            } else {
                RunVoteMix(iClient);
            }
        }
    }

    return 0;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient           Client index.
 * @param iArgs             Number of parameters.
 */
Action Cmd_ForceMix(int iClient, int iArgs)
{
    if (!g_bGamemodeAvailable) {
        return Plugin_Continue;
    }

    if (InSecondHalfOfRound())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "SECOND_HALF_OF_ROUND", iClient);
        return Plugin_Handled;
    }

    if (IsRoundStarted())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_STARTED", iClient);
        return Plugin_Handled;
    }

    if (IsMixStateInProgress())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ALREADY_IN_PROGRESS", iClient);
        return Plugin_Handled;
    }

    ShowMixMenu(iClient, .bForce = true);

    return Plugin_Handled;
}

/**
 * Start voting.
 *
 * @param iInitiator         Client index.
 */
void RunVoteMix(int iInitiator)
{
    int iTotalPlayers;
    int[] iPlayers = new int[MaxClients];

    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        int iTeam = GetClientTeam(iClient);

        if (iTeam == TEAM_INFECTED || iTeam == TEAM_SURVIVOR) {
            iPlayers[iTotalPlayers ++] = iClient;
        }
    }

    NativeVote hVote = new NativeVote(HandlerVoteMix, NativeVotesType_Custom_YesNo);
    hVote.Initiator = iInitiator;
    hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
public Action HandlerVoteMix(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
    switch (tAction)
    {
        case VoteAction_Display:
        {
            char sVoteDisplayMessage[128];

            ExecuteForward_OnDrawVoteTitle(g_iMixIndex, iParam1, sVoteDisplayMessage, sizeof(sVoteDisplayMessage));

            hVote.SetDetails(sVoteDisplayMessage);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: {
            hVote.DisplayFail();
        }

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO
            || g_eMixState != MixState_Voting
            || IsRoundStarted())
            {
                hVote.DisplayFail();

                SetMixState(MixState_None);
                g_iMixIndex = INVALID_INDEX;

                return Plugin_Continue;
            }

            hVote.DisplayPass();

            RunPlayerMix();
        }

        case VoteAction_End: hVote.Close();
    }

    return Plugin_Continue;
}

void RunPlayerMix()
{
    g_iAbortDelay = GetTime() + GetMixAbortDelay(g_iMixIndex);

    SetAllClientSpectator();

    if (SetMixState(MixState_InProgress) == Plugin_Continue) {
        FinishPlayerMix();
    }
}

/**
 * Initiation of the end of the command mix.
 */
void FinishPlayerMix()
{
    SetMixState(MixState_None, false);
    g_iMixIndex = INVALID_INDEX;
}

/**
 * Returns players to teams before the mix starts.
 */
void AbortPlayerMix()
{
    SetMixState(MixState_None, true);
    g_iMixIndex = INVALID_INDEX;

    SetAllClientSpectator();

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (!g_bClientMixMember[iClient]) {
            continue;
        }

        SetupClientTeam(iClient, g_iClientTeamBeforePlayerMix[iClient]);
    }
}

/**
 * Checks if a mix is ​​currently running.
 *
 * @return                  Returns true if a mix is ​​currently.
 *                          in progress, otherwise false.
 */
bool IsMixStateInProgress() {
    return g_eMixState != MixState_None;
}

bool IsRoundStarted() {
    return g_bRoundIsLive;
}

int GetMixMinPlayers(int iIndex)
{
    MixInfo mix;
    GetArrayArray(g_hMixList, iIndex, mix);

    return mix.minPlayers;
}

int GetMixAbortDelay(int iIndex)
{
    MixInfo mix;
    GetArrayArray(g_hMixList, iIndex, mix);

    return mix.abortDelay;
}

/**
 * Returns the number of players in the game.
 *
 * @return                  Client count.
 */
int GetPlayerCount()
{
    int iCount = 0;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (IsValidTeam(GetClientTeam(iClient))) {
            iCount++;
        }
    }

    return iCount;
}

/**
 *
 */
Action SetMixState(MixState eNewMixState, bool bIsFail = false)
{
    Action aReturn = Plugin_Continue;

    if (g_eMixState != eNewMixState)
    {
        aReturn = ExecuteForward_OnChangMixState(g_iMixIndex, g_eMixState, eNewMixState, bIsFail);
        g_eMixState = eNewMixState;
    }

    return aReturn;
}

/**
 *
 */
Action ExecuteForward_OnChangMixState(int iMixIndex, MixState eOldState, MixState eNewState, bool bIsFail = false)
{
    Action aReturn = Plugin_Continue;

    if (GetForwardFunctionCount(g_fwdOnChangeMixState))
    {
        Call_StartForward(g_fwdOnChangeMixState);
        Call_PushCell(iMixIndex);
        Call_PushCell(eOldState);
        Call_PushCell(eNewState);
        Call_PushCell(bIsFail);
        Call_Finish(aReturn);
    }

    return aReturn;
}

/**
 *
 */
void ExecuteForward_OnDrawMenuItem(int iMixIndex, int iClient, char[] sName, int iLength)
{
    if (GetForwardFunctionCount(g_fwdOnDrawMenuItem))
    {
        Call_StartForward(g_fwdOnDrawMenuItem);
        Call_PushCell(iMixIndex);
        Call_PushCell(iClient);
        Call_PushStringEx(sName, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
        Call_PushCell(iLength);
        Call_Finish();
    }
}


/**
 *
 */
void ExecuteForward_OnDrawVoteTitle(int iMixIndex, int iClient, char[] sTitle, int iLength)
{
    if (GetForwardFunctionCount(g_fwdOnDrawVoteTitle))
    {
        Call_StartForward(g_fwdOnDrawVoteTitle);
        Call_PushCell(iMixIndex);
        Call_PushCell(iClient);
        Call_PushStringEx(sTitle, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
        Call_PushCell(iLength);
        Call_Finish();
    }
}

/**
 * Sets everyone to spectator team.
 */
void SetAllClientSpectator()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        SetupClientTeam(iClient, TEAM_SPECTATOR);
    }
}

/**
 * Checks if the current round is the second.
 *
 * @return                  Returns true if is second round, otherwise false.
 */
bool InSecondHalfOfRound() {
    return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}

/**
 * Sets the client team.
 *
 * @param iClient           Client index.
 * @param iTeam             Client team.
 * @return                  Returns true if success.
 */
bool SetupClientTeam(int iClient, int iTeam)
{
    if (GetClientTeam(iClient) == iTeam) {
        return true;
    }

    if (iTeam == TEAM_INFECTED || iTeam == TEAM_SPECTATOR)
    {
        ChangeClientTeam(iClient, iTeam);
        return true;
    }

    int iBot = FindSurvivorBot();
    if (iTeam == TEAM_SURVIVOR && iBot != -1)
    {
        if (g_bDHookAvailable)
        {
            ChangeClientTeam(iClient, TEAM_NONE);
            SetHumanSpec(iBot, iClient);
            TakeOverBot(iClient);
        }

        else {
            ExecuteCheatCommand(iClient, "sb_takecontrol");
        }

        return true;
    }

    return false;
}

/**
 * Hack to execute cheat commands.
 */
void ExecuteCheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
    int iFlags = GetCommandFlags(sCmd);
    SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
    FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
    SetCommandFlags(sCmd, iFlags);
}

/**
 * Finds a free bot.
 *
 * @return                  Bot index, otherwise -1.
 */
int FindSurvivorBot()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient)
        || !IsFakeClient(iClient)
        || !IsClientSurvivor(iClient)) {
            continue;
        }

        return iClient;
    }

    return -1;
}

/**
 *
 */
bool IsValidTeam(int iTeam) {
    return (iTeam == TEAM_SURVIVOR || iTeam == TEAM_INFECTED);
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Is the game mode versus or scavenge.
 *
 * @param sGameMode         A string containing the name of the game mode.
 *
 * @return                  Returns true if verus, otherwise false.
 */
bool IsAvaibleMode(const char[] sGameMode)
{
    return StrEqual(sGameMode, GAMEMODE_VERSUS, false)
    || StrEqual(sGameMode, GAMEMODE_VERSUS_REALISM, false)
    || StrEqual(sGameMode, GAMEMODE_SCAVENGE, false);
}
