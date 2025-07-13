#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>


public Plugin myinfo = {
    name        = "[MixTeam] Random",
    author      = "TouchMe",
    description = "Adds random mix",
    version     = "build_0007",
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

    int iMaxTeamSize = FindConVar("survivor_limit").IntValue;

    Handle hSurvivorTeam = CreateArray();
    Handle hInfectedTeam = CreateArray();

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
            continue;
        }

        switch (GetClientPrevTeam(iClient))
        {
            case TEAM_SURVIVOR: PushArrayCell(hSurvivorTeam, iClient);

            case TEAM_INFECTED: PushArrayCell(hInfectedTeam, iClient);
        }
    }

    int iSurvivorTeamSize = GetArraySize(hSurvivorTeam);
    int iInfectedTeamSize = GetArraySize(hInfectedTeam);

    if (iSurvivorTeamSize < iMaxTeamSize / 2 || iInfectedTeamSize < iMaxTeamSize / 2)
    {
        Handle hAll = CreateArray();

        MergeArrays(hAll, hSurvivorTeam);
        MergeArrays(hAll, hInfectedTeam);

        int iSize = 0;
        while ((iSize = GetArraySize(hAll)) > 0)
        {
            int iRnd = GetRandomInt(0, iSize - 1);
            int iClient = GetArrayCell(hAll, iRnd);
            SetClientTeam(iClient, iSize % 2 == 0 ? TEAM_SURVIVOR : TEAM_INFECTED);
            RemoveFromArray(hAll, iRnd);
        }

        delete hAll;
    }
    else
    {
        Handle hNewSurvivorTeam = CreateArray();
        Handle hNewInfectedTeam = CreateArray();

        for (int iIdx = 0; iIdx < iSurvivorTeamSize / 2; iIdx++)
        {
            int iRnd = GetRandomInt(0, GetArraySize(hSurvivorTeam) - 1);
            PushArrayCell(hNewSurvivorTeam, GetArrayCell(hSurvivorTeam, iRnd));
            RemoveFromArray(hSurvivorTeam, iRnd);
        }

        for (int iIdx = 0; iIdx < iInfectedTeamSize / 2; iIdx++)
        {
            int iRnd = GetRandomInt(0, GetArraySize(hInfectedTeam) - 1);
            PushArrayCell(hNewInfectedTeam, GetArrayCell(hInfectedTeam, iRnd));
            RemoveFromArray(hInfectedTeam, iRnd);
        }

        MergeArrays(hNewInfectedTeam, hSurvivorTeam);
        MergeArrays(hNewSurvivorTeam, hInfectedTeam);

        for (int iIdx = 0; iIdx < GetArraySize(hNewSurvivorTeam); iIdx++) {
            SetClientTeam(GetArrayCell(hNewSurvivorTeam, iIdx), TEAM_SURVIVOR);
        }

        for (int iIdx = 0; iIdx < GetArraySize(hNewInfectedTeam); iIdx++) {
            SetClientTeam(GetArrayCell(hNewInfectedTeam, iIdx), TEAM_INFECTED);
        }

        delete hNewSurvivorTeam;
        delete hNewInfectedTeam;
    }

    delete hSurvivorTeam;
    delete hInfectedTeam;

    return Plugin_Continue;
}

/**
 * Appends all elements from a source array into a destination array.
 *
 * @param hDst  The destination array to which elements will be added.
 * @param hSrc  The source array from which elements will be copied.
 *
 * Note: This function does not clear the destination array.
 *       Elements from hSrc will be pushed to the end of hDst.
 */
void MergeArrays(Handle hDst, Handle hSrc)
{
    int iSize = GetArraySize(hSrc);
    for (int iIdx = 0; iIdx < iSize; iIdx ++) {
        PushArrayCell(hDst, GetArrayCell(hSrc, iIdx));
    }
}
