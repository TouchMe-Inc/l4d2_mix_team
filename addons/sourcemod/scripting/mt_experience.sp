#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>
#include <steamworks>
#include <colors>


public Plugin myinfo = {
    name        = "MixTeamExperience",
    author      = "SirP, TouchMe",
    description = "Adds mix team by steamworks stats",
    version     = "build_0002",
    url         = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_experience.phrases"

/**
 * Teams.
 */
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

// Other
#define APP_L4D2                550

#define MIN_PLAYERS             6


enum struct PlayerInfo {
    int id;
    float rating;
}

enum struct PlayerStats {
    int playedTime;
    int gamesWon;
    int gamesLost;
    int killBySilenced;
    int killBySmg;
    int killByChrome;
    int killByPump;
}

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

public Action OnDrawVoteTitle(int iMixIndex, int iClient, char[] szTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(szTitle, iLength, "%T", "VOTE_TITLE", iClient);

    return Plugin_Stop;
}

public Action OnDrawMenuItem(int iMixIndex, int iClient, char[] szTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(szTitle, iLength, "%T", "MENU_ITEM", iClient);

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

    Handle hPlayers = CreateArray(sizeof(PlayerInfo));
    PlayerInfo tPlayer;
    PlayerStats tPlayerStats;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
            continue;
        }

        SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", tPlayerStats.playedTime);
        SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", tPlayerStats.gamesWon);
        SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", tPlayerStats.gamesLost);
        SteamWorks_GetStatCell(iClient, "Stat.smg_silenced.Kills.Total", tPlayerStats.killBySilenced);
        SteamWorks_GetStatCell(iClient, "Stat.smg.Kills.Total", tPlayerStats.killBySmg);
        SteamWorks_GetStatCell(iClient, "Stat.shotgun_chrome.Kills.Total", tPlayerStats.killByChrome);
        SteamWorks_GetStatCell(iClient, "Stat.pumpshotgun.Kills.Total", tPlayerStats.killByPump);

        tPlayer.id = iClient;
        tPlayer.rating = CalculateRatingByPlayerStats(tPlayerStats);

        if (tPlayer.rating <= 0.0)
        {
            CPrintToChatAll("%t", "PLAYER_UNKNOWN_RATING", iClient);
            Call_AbortMix();
            return Plugin_Handled;
        }

        PushArrayArray(hPlayers, tPlayer);
    }

    SortADTArrayCustom(hPlayers, SortPlayerByRating);

    // Balance
    int iPlayers = GetArraySize(hPlayers);
    int iMaxPerTeam = iPlayers / 2;

    int iSurvivorCount = 0;
    int iInfectedCount = 0;
    float fSurvivorRating = 0.0, fInfectedRating = 0.0;

    for (int iIndex = iPlayers - 1; iIndex >= 0; iIndex--)
    {
        GetArrayArray(hPlayers, iIndex, tPlayer);

        bool bAssignSurvivor = (iSurvivorCount < iMaxPerTeam &&
            (fSurvivorRating <= fInfectedRating || iInfectedCount >= iMaxPerTeam));

        SetClientTeam(tPlayer.id, bAssignSurvivor ? TEAM_SURVIVOR : TEAM_INFECTED);

        if (bAssignSurvivor) {
            fSurvivorRating += tPlayer.rating;
            iSurvivorCount++;
        } else {
            fInfectedRating += tPlayer.rating;
            iInfectedCount++;
        }
    }

    return Plugin_Continue;
}

/**
 *
 */
public void OnClientConnected(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    /*
     * Get player stats.
     */
    SteamWorks_RequestStats(iClient, APP_L4D2);
}

float CalculateRatingByPlayerStats(PlayerStats tPlayerStats)
{
    float fPlayedHours = float(tPlayerStats.playedTime) / 3600.0;

    if (fPlayedHours <= 0.0) {
        return 0.0;
    }

    int iKillTotal = tPlayerStats.killByChrome + tPlayerStats.killByPump + tPlayerStats.killBySilenced + tPlayerStats.killBySmg;
    int iVersusGame = tPlayerStats.gamesWon + tPlayerStats.gamesLost;
    float fWinRounds = 0.5;

    if(iVersusGame >= 700) {
        fWinRounds = float(tPlayerStats.gamesWon) / float(iVersusGame);
    }

    return fWinRounds * (0.55 * fPlayedHours + float(iKillTotal) * 0.005);
}

/**
  * @param indexFirst    First index to compare.
  * @param indexSecond   Second index to compare.
  * @param hArrayList    Array that is being sorted (order is undefined).
  * @param hndl          Handle optionally passed in while sorting.
  *
  * @return              -1 if first should go before second
  *                      0 if first is equal to second
  *                      1 if first should go after second
  */
int SortPlayerByRating(int indexFirst, int indexSecond, Handle hArrayList, Handle hndl)
{
    PlayerInfo tPlayerFirst, tPlayerSecond;

    GetArrayArray(hArrayList, indexFirst, tPlayerFirst);
    GetArrayArray(hArrayList, indexSecond, tPlayerSecond);

    if (tPlayerFirst.rating < tPlayerSecond.rating) {
        return -1;
    }

    if (tPlayerFirst.rating > tPlayerSecond.rating) {
        return 1;
    }

    return 0;
}
