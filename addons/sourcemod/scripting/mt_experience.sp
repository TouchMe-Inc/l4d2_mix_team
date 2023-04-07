#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <ripext>


#define VALVEURL "http://api.steampowered.com/ISteamUserStats/GetUserStatsForGame/v0002/?appid=550"

char VALVEKEY[64];  //steam web api key
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
ConVar not_allow_npublicinfo, g_team_allocation;
Handle h_mixTimer;
int g_iPlayerRP[MAXPLAYERS + 1] = {-1};
int g_iTeamData[3];
int g_iCheckingClientRPid = 0;          
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
    version = "1.0"
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
    GetKeyinFile();
    g_Lplayers = new ArrayList(sizeof(Player));
    temp_prp = CreateConVar("itemp_prp", "-1", "TempVariable");
    not_allow_npublicinfo = CreateConVar("sm_mix_allow_hide_gameinfo", "1", "如果有玩家隐藏游戏信息，mix是否继续分队。隐藏的玩家将按一个固定值计算。1 - 继续分队。0 - 阻止继续");
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
 * The entire process of mix execution, because the entire code will 
 * continue to execute when executing the callback function of request.Get(), 
 * so use timer to loop check the query results.
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
        if (!IsClientInGame(g_iCheckingClientRPid) || !IsMixMember(g_iCheckingClientRPid)) {
            g_iCheckingClientRPid++;
        }
        else
        {
            break;
        }
    }
    
    if(!g_bchecking){
        g_bchecking = true;
        GetClientRP(g_iCheckingClientRPid);
    }
    if (g_iCheckingClientRPid > MaxClients) g_bcheckfinished = true;
    if (!g_bcheckfinished){
        if (temp_prp.IntValue == -1){
            return Plugin_Continue;
        } else {
            g_iPlayerRP[g_iCheckingClientRPid] = temp_prp.IntValue;
            g_bchecking = false;
        }
        //TODO: Client index 1464813651 is invalid (arg 3)
        //CPrintToChatAll("%t", "SHOW_ONE_RP", g_iCheckingClientRPid, g_iPlayerRP[g_iCheckingClientRPid]);
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
    CallCancelMix();
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

public void OnMixInProgress()
{
    g_Lplayers.Clear();
    g_iCheckingClientRPid = 0;
    g_bchecking = false;
    g_bcheckfinished = false;
    h_mixTimer = CreateTimer(1.0, TimerCallback, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
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
 * Retrieve the data from the global variable "data".
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
 * Retrieve the Steam API key from a file.
 * 
 * @noreturn
 */
void GetKeyinFile()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath),"configs/api_key.txt");

    Handle file = OpenFile(sPath, "r");
    if(file == INVALID_HANDLE)
    {
        SetFailState("file configs/api_key.txt doesn't exist!");
        return;
    }

    char readData[256];
    if(!IsEndOfFile(file) && ReadFileLine(file, readData, sizeof(readData)))
    {
        Format(VALVEKEY, sizeof(VALVEKEY), "%s", readData);
    }
}


/**
 * Retrieve the player's experience rating and save it to the RP array, 
 * with a fixed value being set if it fails.
 * 
 * @param iClient player id
 * @return Client Rankpoint (The return value is highly likely to be -1, and it must be checked multiple times.)
 */
int GetClientRP(int iClient)
{
    temp_prp.IntValue = -1;
    Player iPlayer;
    iPlayer.id = iClient;
    // 获取信息
    char URL[1024];
    char id64[64];
    GetClientAuthId(iPlayer.id,AuthId_SteamID64,id64,sizeof(id64));
    if(StrEqual(id64,"STEAM_ID_STOP_IGNORING_RETVALS")){
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks) + 
            100000.0*0.005*1.35);
        iPlayer.rankpoint = RoundToNearest(rp);
        temp_prp.IntValue = iPlayer.rankpoint;
        PrintToConsoleAll("%N(X)  %i=%f*(0.55*%i*+%i*1+100000*0.005*(1+0.35))",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);
        CPrintToChatAll("%t", "FAIL_CANT_GET_ID", iClient, temp_prp.IntValue);
        return temp_prp.IntValue;
    }
    Format(URL,sizeof(URL),"%s&key=%s&steamid=%s",VALVEURL,VALVEKEY,id64);
    HTTPRequest request = new HTTPRequest(URL);
    request.Get(OnReceived, iClient);
    PrintToServer("%s",URL);
    return temp_prp.IntValue;    
}

/**
 * HTTP callback function for calculating the player's RP.
 * 
 * @param id player id
 * @noreturn The RP of the client will be saved in "temp_prp.IntValue".
 */
public void OnReceived(HTTPResponse response, int id)
{
    Player iPlayer;
    iPlayer.id = id;
    char buff[50];
    if ((response.Status) == HTTPStatus_Forbidden) {
        PrintToChatAll("%t", "INVAILD_RESPONSE");
        CallCancelMix();
    }
    if (response.Data == null) {
        PrintToServer("Invalid JSON response");
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks) + 
            100000.0*0.005*1.35);
        iPlayer.rankpoint = RoundToNearest(rp);
        temp_prp.IntValue = iPlayer.rankpoint;
        CPrintToChatAll("%t", "FAIL_CANT_GET_INFO", id, temp_prp.IntValue);
        PrintToConsoleAll("%N(X)  %i=%f*(0.55*%i*+%i*1+100000*0.005*(1+0.35))",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);
        return;  
    }
    JSONObject json = view_as<JSONObject>(response.Data);
    if (json.HasKey("playerstats")){
        json=view_as<JSONObject>(json.Get("playerstats"));
    }
    else
    {
        PrintToServer("JSON response dont have key `playerstats`");
        iPlayer.gametime = 700;
        iPlayer.tankrocks = 700;
        iPlayer.winrounds = 0.5;
        float rp = iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks) + 
            100000.0*0.005*1.35);
        iPlayer.rankpoint = RoundToNearest(rp);
        temp_prp.IntValue = iPlayer.rankpoint;
        if (not_allow_npublicinfo.IntValue > 0){
            CPrintToChatAll("%t", "FAIL_PLAYER_HIDE_INFO_CONTINUE", id, temp_prp.IntValue);
            PrintToConsoleAll("%N  %i=%f*(0.55*%i*+%i*1+100000*0.005*(1+0.35))",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks);
            return;  
        }else {
            CPrintToChatAll("%t", "FAIL_PLAYER_HIDE_INFO_STOP", id);
            OnMixFailed("");
        }
    }
    JSONArray jsonarray=view_as<JSONArray>(json.Get("stats"));
    for(int j=0;j<jsonarray.Length;j++)
    {
        json=view_as<JSONObject>(jsonarray.Get(j));
        json.GetString("name",buff,sizeof(buff));
        if(StrEqual(buff,"Stat.TotalPlayTime.Total"))		
        {
            iPlayer.gametime = json.GetInt("value")/3600;
        }else if(StrEqual(buff,"Stat.SpecAttack.Tank")){
            iPlayer.tankrocks = json.GetInt("value");
        }else if(StrEqual(buff,"Stat.GamesLost.Versus")){
            iPlayer.versuslose = json.GetInt("value");
        }else if(StrEqual(buff,"Stat.GamesWon.Versus")){
            iPlayer.versuswin = json.GetInt("value");
        }else if(StrEqual(buff,"Stat.smg_silenced.Kills.Total")){
            iPlayer.smgkills += json.GetInt("value");
        }else if(StrEqual(buff,"Stat.smg.Kills.Total")){
            iPlayer.smgkills += json.GetInt("value");
        }else if(StrEqual(buff,"Stat.shotgun_chrome.Kills.Total")){
            iPlayer.shotgunkills += json.GetInt("value");
        }else if(StrEqual(buff,"Stat.pumpshotgun.Kills.Total")){
            iPlayer.shotgunkills += json.GetInt("value");
        }
    }
    iPlayer.versustotal = iPlayer.versuswin + iPlayer.versuslose;
    iPlayer.winrounds = float(iPlayer.versuswin) / float(iPlayer.versustotal);
    if(iPlayer.versustotal < 700){
        iPlayer.winrounds = 0.5;
    }
    int killtotal = iPlayer.smgkills + iPlayer.shotgunkills;
    float shotgunperc = float(iPlayer.shotgunkills) / float(killtotal);
    float rpm = float(iPlayer.tankrocks) / float(iPlayer.gametime);
    float rp = iPlayer.winrounds * (0.55 * float(iPlayer.gametime) + float(iPlayer.tankrocks) * rpm + 
        (killtotal) * 0.005 * (1.0 + shotgunperc));

    iPlayer.rankpoint = RoundToNearest(rp);
    temp_prp.IntValue = iPlayer.rankpoint;
    PrintToConsoleAll("%N  %i=%f*(0.55*%i*+%i*%f+%i*0.005*(1+%f))",iPlayer.id, iPlayer.rankpoint, iPlayer.winrounds ,iPlayer.gametime, iPlayer.tankrocks, rpm,
        killtotal, shotgunperc);
}
