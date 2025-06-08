#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>


public Plugin myinfo = {
    name        = "MixTeamRandom",
    author      = "TouchMe",
    description = "Adds random mix",
    version     = "build_0005",
    url         = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_random.phrases"

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define MIN_PLAYERS             4


int g_iThisMixIndex = -1;

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public void OnAllPluginsLoaded() {
    g_iThisMixIndex = AddMix(MIN_PLAYERS, 0);
}

public Action OnDrawVoteTitle(int iMixIndex, int iClient, char[] sTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(sTitle, iLength, "%T", "VOTE_TITLE", iClient);

    return Plugin_Stop;
}

public Action OnDrawMenuItem(int iMixIndex, int iClient, char[] sTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(sTitle, iLength, "%T", "MENU_ITEM", iClient);

    return Plugin_Stop;
}

/**
 * Starting the mix.
 */
public Action OnChangeMixState(int iMixIndex, MixState eOldState, MixState eNewState, bool bIsFail)
{
    if (iMixIndex != g_iThisMixIndex || eNewState != MixState_InProgress) {
        return Plugin_Continue;
    }

    Handle hPlayers = CreateArray();

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
            continue;
        }

        PushArrayCell(hPlayers, iClient);
    }

    for (int iPlayers, iIndex, iClient;;)
    {
        iPlayers = GetArraySize(hPlayers);

        if (!iPlayers) {
            break;
        }

        iIndex = GetRandomInt(0, iPlayers - 1);
        iClient = GetArrayCell(hPlayers, iIndex);

        SetClientTeam(iClient, iPlayers % 2 == 0 ? TEAM_INFECTED : TEAM_SURVIVOR);
        RemoveFromArray(hPlayers, iIndex);
    }

    CloseHandle(hPlayers);

    return Plugin_Continue;
}
