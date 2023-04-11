#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <steamworks>

enum struct Player{
    int id;
    int rankpoint;  // Unfortunately, it's zero here.
    int gametime;	
    int tankrocks;	
    float winrounds;
    int versustotal;
    int versuswin;
    int versuslose;
    int smgkills;
    int shotgunkills;
}
ArrayList g_Lteam1, g_Lteam2, g_Lplayers;
Player tempPlayer;
ConVar temp_prp;
ConVar g_team_allocation;
Handle h_mixTimer;
int g_iPlayerRP[MAXPLAYERS + 1] = {-1};
int g_iTeamData[3];
int g_iCheckingClientRPid = 0;  
int g_iMaxRetry = 5;        
bool g_bchecking = false;               // Retrieve the RP status of a single player.
bool g_bcheckfinished = false;          // All members of the mix have been checked.

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)

public Plugin myinfo = { 
    name = "MixTeamExperience",
    author = "SirP",
    description = "Adds mix team by game experience",
    version = "1.1.0"
};


#define TRANSLATIONS            "mt_experience.phrases"

#define TEAM_SURVIVOR           2 
#define TEAM_INFECTED           3

#define MIN_PLAYERS             1

// Macros
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))


/**
 * Loads dictionary files. On failure, stops the plugin execution.
 * 
 * @noreturn
 */
void InitTranslations()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

    if (FileExists(sPath)) {
        LoadTranslations(TRANSLATIONS);
    } else {
        SetFailState("Path %s not found", sPath);
    }
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart() {
    InitTranslations();
    g_Lplayers = new ArrayList(sizeof(Player));
    temp_prp = CreateConVar("itemp_prp", "-1", "TempVariable");
    g_team_allocation = CreateConVar("sm_mix_exp_type", "1", "MIX的分队算法。1 - 平均分差最小。0 - 尽量2带2");

}

public void OnAllPluginsLoaded() {
    AddMixType("exp", MIN_PLAYERS, 0);
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
    Format(sTitle, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
    Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}




/**
 * The main process of MIX. 
 * Although there may be more efficient ways to implement it, I don't want to change it XD
 * 
 * @noreturn    
 */

public Action TimerCallback(Handle timer)
{
    if (g_iCheckingClientRPid == 0){
        CPrintToChatAll("%t", "START_GET_INFO");
        g_iCheckingClientRPid++;
    }
    while (g_iCheckingClientRPid <= MaxClients){
        if (g_bchecking) break;
        if (!IsClientInGame(g_iCheckingClientRPid) || !IsMixMember(g_iCheckingClientRPid) || IsFakeClient(g_iCheckingClientRPid)) {
            g_iCheckingClientRPid++;
            
        }
        else
        {
            break;
        }
    }
    
    if(!g_bchecking){
        g_bchecking = true;

        int res = GetClientRP(g_iCheckingClientRPid);
        if (res == -2){
            if (g_iMaxRetry > 0){
                CPrintToChatAll("%t", "FAIL_PLAYER_INFO_RETRY", g_iCheckingClientRPid, g_iMaxRetry);
                temp_prp.IntValue = -1;
                g_iMaxRetry--;
                g_bchecking = false;
                return Plugin_Continue;
            }
            else {
                CPrintToChatAll("%t", "FAIL_PLAYER_HIDE_INFO_STOP", g_iCheckingClientRPid);
                OnMixFailed("");
                CallCancelMix();
                return Plugin_Stop;  
            }
        }
    }
    g_iMaxRetry = 5;
    if (g_iCheckingClientRPid > MaxClients) g_bcheckfinished = true;
    if (!g_bcheckfinished){
        if (temp_prp.IntValue == -1){
            return Plugin_Continue;
        } else {
            g_iPlayerRP[g_iCheckingClientRPid] = temp_prp.IntValue;
            g_bchecking = false;
        }
        g_bchecking = false;

        g_iCheckingClientRPid++;
        if (g_iCheckingClientRPid <= MaxClients){
            return Plugin_Continue;
        }
    }
    
    CPrintToChatAll("%t", "CHECK_DONE");
    MixMembers();
    CallEndMix();
    return Plugin_Stop;
}

/** 
 * Called when the mix operation fails.
 * 
 * @noreturn
 */
public void OnMixFailed(const char[] sMixName){
    KillTimer(h_mixTimer);
    h_mixTimer = INVALID_HANDLE;
}


/**
 * After obtaining the RP of all team members, 
 * traverse and save the function's results that have the smallest point difference between the two sides.
 * 
 * @noreturn
 * */
void MixMembers(){
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || !IsMixMember(iClient)) {
            continue;
        }
        if (g_iPlayerRP[iClient] == -1) continue;
        tempPlayer.id = iClient;
        tempPlayer.rankpoint = g_iPlayerRP[iClient];
        g_Lplayers.PushArray(tempPlayer);
    }
    g_Lplayers.SortCustom(SortByRank);
    int surrankpoint, infrankpoint = 0;

    switch (g_team_allocation.IntValue){
        case 0: 
        {
            balance_diff();
        }
        case 1: 
        {
            min_diff();
        }
        default:  
        {
            min_diff();
        }
    }

    PrintToConsoleAll("%t", "EXP_EQUATION");
    PrintToConsoleAll("-----------------------------------------------------------");

    for (int i = 0; i < g_Lteam1.Length; i++)
    {
        g_Lteam1.GetArray(i, tempPlayer);
        if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, TEAM_SURVIVOR);
        surrankpoint += g_iPlayerRP[tempPlayer.id];
    }
    for (int i = 0; i < g_Lteam2.Length; i++)
    {
        g_Lteam2.GetArray(i, tempPlayer);
        if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, TEAM_INFECTED);
        infrankpoint += g_iPlayerRP[tempPlayer.id];
    }
    g_iTeamData[0] = surrankpoint;
    g_iTeamData[1] = infrankpoint;
    g_iTeamData[2] = abs(surrankpoint - infrankpoint);
    CreateTimer(2.0, PrintResult);
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */

public Action OnMixInProgress()
{
    g_Lplayers.Clear();
    g_iCheckingClientRPid = 0;
    g_bchecking = false;
    g_bcheckfinished = false;
    h_mixTimer = CreateTimer(1.0, TimerCallback, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
    return Plugin_Handled;
}

int SortByRank(int indexFirst, int indexSecond, Handle hArrayList, Handle hndl)
{
    Player tPlayerFirst, tPlayerSecond;

    GetArrayArray(hArrayList, indexFirst, tPlayerFirst);
    GetArrayArray(hArrayList, indexSecond, tPlayerSecond);

    if (g_iPlayerRP[tPlayerFirst.id] < g_iPlayerRP[tPlayerSecond.id]) {
        return -1;
    }

    if (g_iPlayerRP[tPlayerFirst.id] > g_iPlayerRP[tPlayerSecond.id]) {
        return 1;
    }

    return 0;
}

/**
 * Calculate the absolute value.
 * 
 * @param value
 * @return The absolute value of "value".
 */
int abs(int value){
    if (value < 0) return -value;
    return value;   
}


/**
 * Calculate the difference in RP between the two groups of players.
 * 
 * @param array1    The first group of players.
 * @param array2    The second group of players.
 * @return          Point differential.
 */
int diff_sum(ArrayList array1, ArrayList array2)
{
    int sum1 = 0;
    int sum2 = 0;
    for (int i = 0; i < array1.Length; i++)
    {
        array1.GetArray(i, tempPlayer);
        sum1 += g_iPlayerRP[tempPlayer.id];
    }
    for (int i = 0; i < array2.Length; i++)
    {
        array2.GetArray(i, tempPlayer);
        sum2 += g_iPlayerRP[tempPlayer.id];
    }
    return abs(sum1 - sum2);
}

/**
 * Output the result when the mix is finished.
 * Retrieve the data from the global variable "g_iTeamData".
 * 
 * g_iTeamData[0] - Survivors RP
 * g_iTeamData[1] - Infected RP
 * g_iTeamData[2] - difference between the two teams
 * 
 * This approach is necessary as it appears that passing multiple arguments into 
 * the "CreateTimer()" function is not possible (or beyond my current ability).
 */
public Action PrintResult(Handle timer)
{
    CPrintToChatAll("%t", "MIX_FINISH");
    CPrintToChatAll("%t", "SUR_TOTAL_RP", g_iTeamData[0]);
    CPrintToChatAll("%t", "INF_TOTAL_RP", g_iTeamData[1]);
    CPrintToChatAll("%t", "DIFF_RP", g_iTeamData[2]);
    CPrintToChatAll("%t", "HINT_CONSOLE");
    return Plugin_Stop;
}


/**
 * Simply balancing the team.
 * 1368 - 2457
 * This is suitable when at least 2/4 players' roleplaying abilities far surpass those of the remaining players.
 * 
 * @noreturn
 */
void balance_diff()
{
    g_Lplayers.SortCustom(SortByRank);
    ArrayList group1 = new ArrayList();
    ArrayList group2 = new ArrayList();
    group1.Resize(4);
    g_Lplayers.GetArray(0, tempPlayer);  
    group1.SetArray(0,tempPlayer);
    g_Lplayers.GetArray(2, tempPlayer);  
    group1.SetArray(1,tempPlayer);
    g_Lplayers.GetArray(5, tempPlayer);  
    group1.SetArray(2,tempPlayer);
    g_Lplayers.GetArray(7, tempPlayer);  
    group1.SetArray(3,tempPlayer);

    group2.Resize(4);
    g_Lplayers.GetArray(1, tempPlayer);  
    group2.SetArray(0,tempPlayer);
    g_Lplayers.GetArray(3, tempPlayer);  
    group2.SetArray(1,tempPlayer);
    g_Lplayers.GetArray(4, tempPlayer);  
    group2.SetArray(2,tempPlayer);
    g_Lplayers.GetArray(6, tempPlayer);  
    group2.SetArray(3,tempPlayer);

    g_Lteam1 = group1.Clone();
    g_Lteam2 = group2.Clone();
}

/**
 * Find all possible ways of grouping and return the minimum point difference along with
 * the corresponding groupings.
 * This is suitable when the overall skill gap is relatively small.
 * 
 * @noreturn
 */
void min_diff()
{
    g_Lplayers.SortCustom(SortByRank);
    int maxdiff = 2147483647;

    for (int i = 0; i < g_Lplayers.Length - 3; i++)
    {
        for (int j = i + 1; j < g_Lplayers.Length - 2; j++)
        {
            for (int k = j + 1; k < g_Lplayers.Length - 1; k++)
            {
                for (int l = k + 1; l < g_Lplayers.Length; l++)
                {
                    ArrayList group1 = new ArrayList();
                    group1.Resize(4);
                    g_Lplayers.GetArray(i, tempPlayer);  
                    group1.SetArray(0,tempPlayer);
                    g_Lplayers.GetArray(j, tempPlayer);  
                    group1.SetArray(1,tempPlayer);
                    g_Lplayers.GetArray(k, tempPlayer);  
                    group1.SetArray(2,tempPlayer);
                    g_Lplayers.GetArray(l, tempPlayer);  
                    group1.SetArray(3,tempPlayer);

                    int m, n, o, p;
                    for (m=0; m<g_Lplayers.Length; m++){
                        if (m != i && m != j && m != k && m != l) break;
                    }
                    for (n=0; n<g_Lplayers.Length; n++){
                        if (n != i && n != j && n != k && n != l && n != m) break;
                    }
                    for (o=0; o<g_Lplayers.Length; o++){
                        if (o != i && o != j && o != k && o != l && o != m && o != n) break;
                    }
                    for (p=0; p<g_Lplayers.Length; p++){
                        if (p != i && p != j && p != k && p != l && p != m && p != n && p != o) break;
                    }                    
                    
                    ArrayList group2 = new ArrayList();
                    group2.Resize(4);
                    g_Lplayers.GetArray(m, tempPlayer);  
                    group2.SetArray(0,tempPlayer);
                    g_Lplayers.GetArray(n, tempPlayer);  
                    group2.SetArray(1,tempPlayer);
                    g_Lplayers.GetArray(o, tempPlayer);  
                    group2.SetArray(2,tempPlayer);
                    g_Lplayers.GetArray(p, tempPlayer);  
                    group2.SetArray(3,tempPlayer);

                    int diff = diff_sum(group1, group2);
                    if (diff < maxdiff)
                    {
                        maxdiff = diff;
                        if (g_Lteam1 != INVALID_HANDLE){
                            g_Lteam1.Resize(0);
                        }
                        if (g_Lteam2 != INVALID_HANDLE){
                            g_Lteam2.Resize(0);
                        }
                        g_Lteam1 = group1.Clone();
                        g_Lteam2 = group2.Clone();
                    }
                    delete group1;
                    delete group2;

                }
            }
        }
    }
}


/**
 * Retrieve the player's experience rating and save it to the RP array, 
 * 
 * @param iClient player id
 * @return Client Rankpoint. if failed will return -2
 */
int GetClientRP(int iClient)
{
    Player iPlayer;
    iPlayer.id = iClient;
    bool status = SteamWorks_RequestStats(iClient, 550/*APP L4D2*/);
    SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", iPlayer.gametime);
    iPlayer.gametime = iPlayer.gametime/3600;
    SteamWorks_GetStatCell(iClient, "Stat.SpecAttack.Tank", iPlayer.tankrocks);
    SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", iPlayer.versuslose);
    SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", iPlayer.versuswin);
    iPlayer.versustotal = iPlayer.versuslose + iPlayer.versuswin;
    iPlayer.smgkills = 0;
    int t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.smg_silenced.Kills.Total", t_kills);
    iPlayer.smgkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.smg.Kills.Total", t_kills);
    iPlayer.smgkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.shotgun_chrome.Kills.Total", t_kills);
    iPlayer.shotgunkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.pumpshotgun.Kills.Total", t_kills);
    iPlayer.shotgunkills += t_kills;
    iPlayer.winrounds = float(iPlayer.versuswin) / float(iPlayer.versustotal);
    if(iPlayer.versustotal < 700) iPlayer.winrounds = 0.5;
    iPlayer.rankpoint = Calculate_RP(iPlayer);
    temp_prp.IntValue = iPlayer.rankpoint;
    if (!status){
        return -2;
    }
    return temp_prp.IntValue;
}

/**
 * Calculate the player's RP
 * 
 * @param tPlayer A Player object
 * @return tPlayer's RP
 */
int Calculate_RP(Player tPlayer)
{
    int killtotal = tPlayer.shotgunkills + tPlayer.smgkills;
    float shotgunperc = float(tPlayer.shotgunkills) / float(killtotal);   
    float rpm = float(tPlayer.tankrocks) / float(tPlayer.gametime);
    float rp = tPlayer.winrounds * (0.55 * float(tPlayer.gametime) + float(tPlayer.tankrocks) * rpm + 
        float(killtotal) * 0.005 * (1.0 + shotgunperc));
    PrintToConsoleAll("%N  %f=%f*(0.55*%i*+%i*%f+%i*0.005*(1+%f))",tPlayer.id, rp, tPlayer.winrounds ,tPlayer.gametime, tPlayer.tankrocks, rpm,
        killtotal, shotgunperc);
    CPrintToChatAll("%t", "SHOW_ONE_RP", tPlayer.id, RoundToNearest(rp));
    return RoundToNearest(rp);
}

