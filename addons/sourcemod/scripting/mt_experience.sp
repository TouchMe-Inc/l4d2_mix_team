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

#define MIN_PLAYERS             6

/**
 * Teams.
 */
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

/**
 * SteamWorks application ID.
 * L4D2 uses appID 550 for stats and achievements.
 */
#define APP_L4D2                550

#define INFECTED_COUNT          7   /**< Number of distinct special infected types tracked (incl. Tank). */
#define MAXLENGTH_STATS_KEY     128 /**< Maximum length for stat key strings. */

/** ------------------------------------------------------------------------
 * Rating scale and base offset.
 * Used to transform normalized [0..1] scores into absolute rating points.
 * ---------------------------------------------------------------------- */
#define RATING_MIN  1000.0   /**< Lower bound of rating output range. */
#define RATING_MAX 10000.0   /**< Upper bound of rating output range. */
#define RATING_SPAN (RATING_MAX - RATING_MIN) /**< Span between min and max rating. */

/** ------------------------------------------------------------------------
 * Bayesian priors for win rate stability with small sample sizes.
 * R_ALPHA sets prior weight; R_N0 is the "games played" trust anchor.
 * ---------------------------------------------------------------------- */
#define R_ALPHA 20.0   /**< Pseudo‑matches contributing the prior mean. */
#define R_N0    30.0   /**< Anchor point for confidence weighting. */

/** ------------------------------------------------------------------------
 * Normalization caps for metric scaling.
 * Values at or above the cap normalize to ≈ 1.0 in NormCap().
 * ---------------------------------------------------------------------- */
// Support
#define CAP_SUPPORT_S 12.0  /**< Avg support actions/game (revive + protect + share + util). */

// Friendly fire
#define CAP_FF_PEAK   50.0  /**< Avg friendly‑fire damage/game at full penalty. */

// Infected
#define CAP_INF_ATTACKS_LIFE   1.5   /**< Special attacks per infected life. */
#define CAP_INF_ATTACKS_MIN    2.0   /**< Special attacks per minute alive. */
#define CAP_INF_MOST_DMG_LIFE 50.0   /**< Max damage in a single life. */

// Survivors
#define CAP_KILLS_PER_MIN  8.0   /**< Survivor kills per minute baseline for 1.0 score. */
#define CAP_DMG_PER_MIN   60.0   /**< Survivor damage per minute baseline for 1.0 score. */

/** ------------------------------------------------------------------------
 * Weights for each normalized metric in the final rating.
 * Should sum ≈ 1.0, with W_FF treated as a penalty term.
 * ---------------------------------------------------------------------- */
#define W_WINRATE  0.20  /**< Weight for Bayesian win rate score. */
#define W_INFECTED 0.10  /**< Weight for infected‑side performance. */
#define W_SUPPORT  0.10  /**< Weight for survivor support actions. */
#define W_KILLS    0.25  /**< Weight for survivor kills per minute. */
#define W_DMG      0.25  /**< Weight for survivor damage per minute. */
#define W_FF       0.05  /**< Penalty weight for friendly‑fire damage. */

/**
 * Safety constants to prevent division‑by‑zero and NaN results.
 */
#define EPS 1.0e-6   /**< Minimum non‑zero denominator value. */

/** ------------------------------------------------------------------------
 * Affine transform mapping win rate [0..1] to [-1..1].
 * Used before applying W_WINRATE in final score assembly.
 * ---------------------------------------------------------------------- */
#define WR_AFFINE_SCALE    2.0   /**< Multiply win rate by this before shift. */
#define WR_AFFINE_SHIFT    1.0   /**< Subtract this after scaling. */
#define PRIOR_WINRATE_MEAN 0.5   /**< Neutral prior mean for Bayesian win rate. */

/**
 * Composite metric weights inside sub‑scores.
 */
// Support composition
#define SUPPORT_SHARE_W 0.50  /**< Relative weight for share_per_game in support score. */
#define SUPPORT_UTIL_W  0.25  /**< Relative weight for util_per_game in support score. */

// Time & shrink
#define SECS_PER_MIN     60.0 /**< Seconds in a minute for time conversions. */
#define SHRINK_BASELINE   0.5 /**< Blend target when shrinking non‑versus stats. */

// Infected aggregation
#define INF_RATE_LIFE_W     0.50 /**< Weight for attacks/life in infected score. */
#define INF_RATE_MIN_W      0.50 /**< Weight for attacks/min in infected score. */
#define INF_COMB_RATE_W     0.70 /**< Weight of combined rate term in infected score. */
#define INF_COMB_MOSTDMG_W  0.30 /**< Weight of "most damage" term in infected score. */

// Neutral fallback
#define NEUTRAL_HALF 0.5 /**< Default neutral value when metric is missing/empty. */


/* ---------- Infected class names (order-fixed) ---------- */

static const char g_szInf[INFECTED_COUNT][] =
{
    "Boomer", "Smoker", "Hunter", "Spitter", "Charger", "Jockey", "Tank"
};

/*
We aggregate across firearms, throwables, upgrades, LMG, GL, melee, CS weapons.
This covers Accuracy/HeadAccuracy/Shots/Kills/Damage consistently.
*/
static const char g_szWeap[][32] =
{
    "pistol", "pistol_magnum",
    "smg", "smg_silenced", "smg_mp5",
    "pumpshotgun", "shotgun_chrome", "autoshotgun", "shotgun_spas",
    "rifle", "rifle_ak47", "rifle_desert", "rifle_sg552",
    "hunting_rifle", "sniper_military", "sniper_awp", "sniper_scout",
    "machinegun", "rifle_m60",
    "grenade_launcher",
    "molotov", "pipe_bomb",
    "incendiary_ammo", "explosive_ammo",
    // melee
    "baseball_bat", "chainsaw", "cricket_bat", "crowbar", "electric_guitar",
    "fireaxe", "frying_pan", "katana", "machete", "tonfa",
    "golfclub", "pitchfork", "shovel", "knife"
};

/**
 * Player statistics used for Versus rating (built only from existing SteamDB keys).
 */
enum struct PlayerStatsVS
{
    // Common
    int   iPlayedTimeSec;
    int   iGamesPlayedTotal;
    int   iGamesPlayedVersus;
    int   iGamesWonVersus;
    int   iGamesLostVersus;

    // Support totals (а не avg, считаем потом сами)
    int   iTeamRevivedTotal;
    int   iTeamProtectedTotal;
    int   iKitsSharedTotal;
    int   iPillsSharedTotal;
    int   iAdrenalineSharedTotal;
    int   iDefibsUsedTotal;
    int   iKitsUsedTotal;
    int   iPillsUsedTotal;
    int   iAdrenalineUsedTotal;

    // Friendly fire
    int   iFFDamageTotal;   // NEW: Stat.FFDamage.Total

    // Weapons
    int   iKillsTotal;
    int   iDamageTotal;

    // Infected
    int   iSpecAttack[INFECTED_COUNT];
    int   iTotalSpawns[INFECTED_COUNT];
    int   iTotalLifeSpanSec[INFECTED_COUNT];
    int   iMostDmgOneLife[INFECTED_COUNT];
}

enum struct PlayerInfo {
    int id;
    float rating;
}

int g_iThisMixIndex = -1;


/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
    LoadTranslations("common.phrases");
    RegConsoleCmd("sm_showstatsvs", Cmd_ShowStatsVS, "Show Versus stats + rating");
}

/**
 * Консольная команда sm_showstatsvs <#userid|name>
 * Показывает все поля PlayerStatsVS + итоговый рейтинг.
 */
public Action Cmd_ShowStatsVS(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_showstatsvs <#userid|name>");
        return Plugin_Handled;
    }

    char arg[64];
    GetCmdArg(1, arg, sizeof arg);

    // FindTarget оборачивает ProcessTargetString и сам печатает ошибки
    int target = FindTarget(client, arg);
    if (target <= 0)
        return Plugin_Handled;

    PlayerStatsVS ps;
    FillPlayerStatsVS(target, ps);

    float rating = CalculateVersusRatingFromStats(ps);

    PrintToConsole(client, "===== PlayerStatsVS for %N =====", target);
    PrintToConsole(client, "PlayedTimeSec        : %d", ps.iPlayedTimeSec);
    PrintToConsole(client, "GamesPlayedTotal     : %d", ps.iGamesPlayedTotal);
    PrintToConsole(client, "GamesPlayedVersus    : %d", ps.iGamesPlayedVersus);
    PrintToConsole(client, "GamesWonVersus       : %d", ps.iGamesWonVersus);
    PrintToConsole(client, "GamesLostVersus      : %d", ps.iGamesLostVersus);

    PrintToConsole(client, "TeamRevivedTotal     : %d", ps.iTeamRevivedTotal);
    PrintToConsole(client, "TeamProtectedTotal   : %d", ps.iTeamProtectedTotal);
    PrintToConsole(client, "KitsSharedTotal      : %d", ps.iKitsSharedTotal);
    PrintToConsole(client, "PillsSharedTotal     : %d", ps.iPillsSharedTotal);
    PrintToConsole(client, "AdrenalineSharedTotal: %d", ps.iAdrenalineSharedTotal);
    PrintToConsole(client, "DefibsUsedTotal      : %d", ps.iDefibsUsedTotal);
    PrintToConsole(client, "KitsUsedTotal        : %d", ps.iKitsUsedTotal);
    PrintToConsole(client, "PillsUsedTotal       : %d", ps.iPillsUsedTotal);
    PrintToConsole(client, "AdrenalineUsedTotal  : %d", ps.iAdrenalineUsedTotal);

    PrintToConsole(client, "FFDamageTotal        : %d", ps.iFFDamageTotal);

    PrintToConsole(client, "KillsTotal           : %d", ps.iKillsTotal);
    PrintToConsole(client, "DamageTotal          : %d", ps.iDamageTotal);

    for (int k = 0; k < INFECTED_COUNT; k++)
    {
        PrintToConsole(client, "--- Infected [%s] ---", g_szInf[k]);
        PrintToConsole(client, "SpecAttack           : %d", ps.iSpecAttack[k]);
        PrintToConsole(client, "TotalSpawns          : %d", ps.iTotalSpawns[k]);
        PrintToConsole(client, "TotalLifeSpanSec     : %d", ps.iTotalLifeSpanSec[k]);
        PrintToConsole(client, "MostDmgOneLife       : %d", ps.iMostDmgOneLife[k]);
    }

    PrintToConsole(client, "===== Rating =====");
    PrintToConsole(client, "Versus Rating        : %.2f", rating);
    PrintToConsole(client, "===================");

    return Plugin_Handled;
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

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
            continue;
        }

        tPlayer.id = iClient;
        tPlayer.rating = CalculateVersusRating(iClient);

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
    int iMaxPerTeam = RoundToCeil(float(iPlayers) / 2.0);

    const int iTeamCount = 2;
    int iTeamCounts[iTeamCount] = { 0, 0 };
    float fTeamRatings[iTeamCount] = { 0.0, 0.0 };

    for (int iIndex = iPlayers - 1; iIndex >= 0; iIndex--)
    {
        GetArrayArray(hPlayers, iIndex, tPlayer);

        int iBestTeam = -1;

        for (int t = 0; t < iTeamCount; t++)
        {
            if (iTeamCounts[t] >= iMaxPerTeam)
                continue;

            if (iBestTeam == -1) {
                iBestTeam = t;
                continue;
            }

            switch (FloatCompare(fTeamRatings[t], fTeamRatings[iBestTeam]))
            {
                case -1: {
                    iBestTeam = t;
                    continue;
                }

                case 0: {

                    if (iTeamCounts[t] < iTeamCounts[iBestTeam]) {
                        iBestTeam = t;
                        continue;
                    }
             
                    if (iTeamCounts[t] == iTeamCounts[iBestTeam] && t < iBestTeam) {
                        iBestTeam = t;
                    }
                }
            }
        }

        bool bAssignSurvivor = (iBestTeam == 0); // 0 — Survivors, 1 — Infected

        SetClientTeam(tPlayer.id, bAssignSurvivor ? TEAM_SURVIVOR : TEAM_INFECTED);

        int iTeamIdx = bAssignSurvivor ? 0 : 1;
        fTeamRatings[iTeamIdx] += tPlayer.rating;
        iTeamCounts[iTeamIdx]++;

        CPrintToChatAll("%t", bAssignSurvivor ? "PLAYER_NOW_SURVIVOR" : "PLAYER_NOW_INFECTED", tPlayer.id, tPlayer.rating);
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

/**
 * Collects player stats (Versus) without weapon accuracy/headshot/shots.
 * Keeps only per-weapon kills and damage aggregated across all weapons.
 */
void FillPlayerStatsVS(int iClient, PlayerStatsVS ps)
{
    // General
    SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total",      ps.iPlayedTimeSec);
    SteamWorks_GetStatCell(iClient, "Stat.GamesPlayed.Total",        ps.iGamesPlayedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.GamesPlayed.Versus",       ps.iGamesPlayedVersus);
    SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus",          ps.iGamesWonVersus);
    SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus",         ps.iGamesLostVersus);

    // Support totals
    SteamWorks_GetStatCell(iClient, "Stat.TeamRevived.Total",        ps.iTeamRevivedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.TeamProtected.Total",      ps.iTeamProtectedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.KitsShared.Total",         ps.iKitsSharedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.PillsShared.Total",        ps.iPillsSharedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.AdrenalineShared.Total",   ps.iAdrenalineSharedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.DefibrillatorsUsed.Total", ps.iDefibsUsedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.KitsUsed.Total",           ps.iKitsUsedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.PillsUsed.Total",          ps.iPillsUsedTotal);
    SteamWorks_GetStatCell(iClient, "Stat.AdrenalineUsed.Total",     ps.iAdrenalineUsedTotal);

    // Friendly fire
    SteamWorks_GetStatCell(iClient, "Stat.FFDamage.Total",           ps.iFFDamageTotal);

    char szKey[MAXLENGTH_STATS_KEY];

    // Weapons aggregate: only kills and damage
    ps.iKillsTotal  = 0;
    ps.iDamageTotal = 0;
    
    for (int i = 0; i < sizeof(g_szWeap); i++)
    {
        int iKills = 0, iDmg = 0;

        FormatEx(szKey, sizeof szKey, "Stat.%s.Kills.Total", g_szWeap[i]);
        SteamWorks_GetStatCell(iClient, szKey, iKills);

        FormatEx(szKey, sizeof szKey, "Stat.%s.Damage.Total", g_szWeap[i]);
        SteamWorks_GetStatCell(iClient, szKey, iDmg);

        ps.iKillsTotal  += iKills;
        ps.iDamageTotal += iDmg;
    }

    // Infected
    for (int k = 0; k < INFECTED_COUNT; k++)
    {
        FormatEx(szKey, sizeof szKey, "Stat.SpecAttack.%s", g_szInf[k]);
        SteamWorks_GetStatCell(iClient, szKey, ps.iSpecAttack[k]);

        FormatEx(szKey, sizeof szKey, "Stat.TotalSpawns.%s", g_szInf[k]);
        SteamWorks_GetStatCell(iClient, szKey, ps.iTotalSpawns[k]);

        FormatEx(szKey, sizeof szKey, "Stat.TotalLifeSpan.%s", g_szInf[k]);
        SteamWorks_GetStatCell(iClient, szKey, ps.iTotalLifeSpanSec[k]);

        FormatEx(szKey, sizeof szKey, "Stat.MostDamage1Life.%s", g_szInf[k]);
        SteamWorks_GetStatCell(iClient, szKey, ps.iMostDmgOneLife[k]);
    }
}

float CalculateVersusRatingFromStats(const PlayerStatsVS ps)
{
    // Shares and anchors
    int   iGamesVersus  = ps.iGamesPlayedVersus;
    int   iWinsVersus   = ps.iGamesWonVersus;
    int   iLossesVersus = ps.iGamesLostVersus;

    float fVersusShare = Ratio(float(ps.iGamesPlayedVersus), float(ps.iGamesPlayedTotal)); // доля игр Versus
    float fConfidence  = Ratio(float(iGamesVersus), float(iGamesVersus) + R_N0);            // доверие к выборке

    // Bayesian winrate with prior 0.5
    float fWinrateSmoothed = Ratio(float(iWinsVersus) + R_ALPHA * PRIOR_WINRATE_MEAN,
                                   float(iWinsVersus + iLossesVersus) + R_ALPHA);
    float fWinrateScore = WR_AFFINE_SCALE * fWinrateSmoothed - WR_AFFINE_SHIFT; // [-1, 1]

    // Survivor support per game -> [0,1]
    float fGamesAll         = float(ps.iGamesPlayedTotal);
    float fSharePerGame     = Ratio(float(ps.iKitsSharedTotal + ps.iPillsSharedTotal + ps.iAdrenalineSharedTotal), fGamesAll);
    float fUtilPerGame      = Ratio(float(ps.iDefibsUsedTotal + ps.iKitsUsedTotal + ps.iPillsUsedTotal + ps.iAdrenalineUsedTotal), fGamesAll);
    float fRevivedPerGame   = Ratio(float(ps.iTeamRevivedTotal),   fGamesAll);
    float fProtectedPerGame = Ratio(float(ps.iTeamProtectedTotal), fGamesAll);

    float fSupportRaw   = fRevivedPerGame + fProtectedPerGame + SUPPORT_SHARE_W * fSharePerGame + SUPPORT_UTIL_W * fUtilPerGame;
    float fSupportScore = NormCap(fSupportRaw, CAP_SUPPORT_S);

    // Friendly fire penalty
    float fFfPerGame      = Ratio(float(ps.iFFDamageTotal), fGamesAll);
    float fFfPenaltyScore = NormCap(fFfPerGame, CAP_FF_PEAK);

    // ---------- Offense: корректируем минуты на "простой" и игру за заражённых ----------

    // 1) Суммарное время за заражённых (в секундах) = сумма lifeSpan всех SI (включая Tank)
    int iInfLifeSecSum = 0;
    for (int i = 0; i < INFECTED_COUNT; i++)
    {
        iInfLifeSecSum += ps.iTotalLifeSpanSec[i];
    }

    // 2) Вычитаем 10% общего времени на «ожидания» и всё заражённое время
    float fAdjSecBase     = 0.9 * float(ps.iPlayedTimeSec);              // -10% на простой
    float fAdjSecSurvivor = fAdjSecBase - float(iInfLifeSecSum);         // -время за заражённых
    if (fAdjSecSurvivor < 0.0) fAdjSecSurvivor = 0.0;                    // не даём уйти в минус

    // 3) Минуты выживающего времени (минимум EPS, чтобы не делить на ноль)
    float fMinutesSurvivor = Ratio(fAdjSecSurvivor, SECS_PER_MIN);

    // Survivors: KPM и DPM на откорректированном времени
    float fKillsPerMin = Ratio(float(ps.iKillsTotal),  fMinutesSurvivor);
    float fDmgPerMin   = Ratio(float(ps.iDamageTotal), fMinutesSurvivor);

    float fKillsScore = NormCap(fKillsPerMin, CAP_KILLS_PER_MIN);
    float fDmgScore   = NormCap(fDmgPerMin,   CAP_DMG_PER_MIN);

    // Усадка по доле Versus
    float fKillsScoreStar = fVersusShare * fKillsScore + (1.0 - fVersusShare) * SHRINK_BASELINE;
    float fDmgScoreStar   = fVersusShare * fDmgScore   + (1.0 - fVersusShare) * SHRINK_BASELINE;

    // Infected side
    float fSumRate = 0.0, fSumMost = 0.0;
    int   nCntRate = 0,   nCntMost = 0;

    for (int i = 0; i < INFECTED_COUNT; i++)
    {
        int   iSpecAttacks = ps.iSpecAttack[i];
        int   iSpawns      = ps.iTotalSpawns[i];
        float fLifeMin     = Ratio(float(ps.iTotalLifeSpanSec[i]), SECS_PER_MIN);
        int   iMostDmgLife = ps.iMostDmgOneLife[i];

        bool bHaveLifeRate = (iSpawns > 0);
        bool bHaveMinRate  = (FloatCompare(fLifeMin, EPS) > 0);

        if (bHaveLifeRate || bHaveMinRate)
        {
            float fRateLife = bHaveLifeRate ? Ratio(float(iSpecAttacks), float(iSpawns)) : 0.0;
            float fRateMin  = bHaveMinRate  ? Ratio(float(iSpecAttacks), fLifeMin)       : 0.0;

            float fRateLifeNorm = NormCap(fRateLife, CAP_INF_ATTACKS_LIFE);
            float fRateMinNorm  = NormCap(fRateMin,  CAP_INF_ATTACKS_MIN);

            fSumRate += INF_RATE_LIFE_W * fRateLifeNorm + INF_RATE_MIN_W * fRateMinNorm;
            nCntRate++;
        }

        if (iMostDmgLife > 0)
        {
            fSumMost += LogNorm(float(iMostDmgLife), CAP_INF_MOST_DMG_LIFE);
            nCntMost++;
        }
    }

    float fMeanRate    = (nCntRate > 0) ? (fSumRate / float(nCntRate)) : NEUTRAL_HALF;
    float fMeanMostDmg = (nCntMost > 0) ? (fSumMost / float(nCntMost)) : NEUTRAL_HALF;

    float fInfectedScore = INF_COMB_RATE_W * fMeanRate + INF_COMB_MOSTDMG_W * fMeanMostDmg;

    // Итоговый скор
    float fScore =
          W_WINRATE  * fWinrateScore
        + W_SUPPORT  * fSupportScore
        + W_INFECTED * fInfectedScore
        + W_KILLS    * fKillsScoreStar
        + W_DMG      * fDmgScoreStar
        - W_FF       * fFfPenaltyScore;

    float fScoreClamped = Clamp01(fScore);
    float fRatingNorm   = fConfidence * fScoreClamped;
    return RATING_MIN + RATING_SPAN * fRatingNorm;
}

/**
 * External interface: gets player's statistics and returns their Versus rating.
 *
 * @param iClient  Client index.
 * @return         Player's rating in the range 100..1000.
 */
float CalculateVersusRating(int iClient)
{
    PlayerStatsVS ps;
    FillPlayerStatsVS(iClient, ps);
    return CalculateVersusRatingFromStats(ps);
}

/**
 * Clamp a floating‑point value to the [0.0, 1.0] range using FloatCompare
 * for consistent precision‑safe comparisons.
 *
 * @param x   Input value to clamp.
 * @return    0.0 if x < 0, 1.0 if x > 1, otherwise x unchanged.
 */
stock float Clamp01(float x)
{
    if (FloatCompare(x, 0.0) < 0) return 0.0;
    if (FloatCompare(x, 1.0) > 0) return 1.0;
    return x;
}

/**
 * Safely compute num / den, returning 0.0 if the denominator is
 * less than or equal to EPS (to avoid division‑by‑zero).
 *
 * @param num   Numerator.
 * @param den   Denominator (expected positive).
 * @return      num / den, or 0.0 if den <= EPS.
 */
stock float Ratio(float num, float den)
{
    if (FloatCompare(den, EPS) <= 0) // EPS is the global minimum denominator.
        return 0.0;
    return num / den;
}

/**
 * Normalize a positive metric into the [0.0, 1.0] range by capping
 * it at 'cap' and dividing by that cap. Negative x is treated as 0.
 *
 * @param x     Input metric value.
 * @param cap   Upper bound at which normalized score = 1.0.
 * @return      x / cap, clipped to [0, 1], or 0.0 if cap <= EPS.
 */
stock float NormCap(float x, float cap)
{
    if (FloatCompare(cap, EPS) <= 0)
        return 0.0;

    if (FloatCompare(x, 0.0) < 0) x = 0.0;
    if (FloatCompare(x, cap) > 0) x = cap;

    return x / cap;
}

/**
 * Log‑normalize a positive metric so that growth slows as values
 * approach 'cap'. Uses: log(1 + x) / log(1 + cap), then clamps.
 *
 * @param x     Input metric value (negative treated as 0).
 * @param cap   Value at which normalized score ≈ 1.0.
 * @return      Normalized score in [0, 1], or 0.0 if cap <= EPS
 *              or log(1 + cap) <= EPS.
 */
stock float LogNorm(float x, float cap)
{
    if (FloatCompare(cap, EPS) <= 0)
        return 0.0;

    if (FloatCompare(x, 0.0) < 0)
        x = 0.0;

    float denom = Logarithm(1.0 + cap);
    if (FloatCompare(denom, EPS) <= 0)
        return 0.0;

    return Clamp01(Logarithm(1.0 + x) / denom);
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
