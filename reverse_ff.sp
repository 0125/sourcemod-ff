#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <l4d_myStocks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name 			= "Reverse FF",
	author 			= "RB",
	description 	= "Reverses Friendly Fire",
	version 		= "1.0",
	url 			= "http://www.sourcemod.net/"
};

static	Handle	g_cvarReverseFFEnable = null;				//Toggle reverse ff
static	Handle	g_hFFTimer[MAXPLAYERS+1]; 					//Used to be able to disable the FF timer when they do more FF
static	bool	g_bFFActive[MAXPLAYERS+1]; 					//Stores whether players are in a state of friendly firing teammates
static	int		g_iDamageCache[MAXPLAYERS+1][MAXPLAYERS+1]; //Used to temporarily store Friendly Fire Damage between teammates
static	int		g_iImmuneStatus[MAXPLAYERS+1]; 				//Used to store immune status while & after survivor is under attack from SI
static	int		g_iCarryStatus[MAXPLAYERS+1]; 				//Used to store if survivor is being carried by charger
static	int		g_iPummelStatus[MAXPLAYERS+1]; 				//Used to store if survivor is being pumelled by charger
static	int		g_iDebugMode = 0;							//Used to toggle debug messages
static	int		g_iDebugLog = 1;							//Used to toggle debug logging
static	char	g_sGame[256];								//Game title

public void OnPluginStart() {
	GetGameFolderName(g_sGame, sizeof(g_sGame));
	
	g_cvarReverseFFEnable = CreateConVar("reverse_ff_enable", "1", "Enable reversed friendy fire");
	AutoExecConfig(true, "reverse_ff");
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
	
	if (StrEqual(g_sGame, "left4dead", false) || StrEqual(g_sGame, "left4dead2", false))
	{
		HookEvent("player_bot_replace", event_player_bot_replace);
		HookEvent("bot_player_replace", event_bot_player_replace);
		
		HookEvent("tongue_grab", event_immunityStart);
		HookEvent("tongue_release", event_immunityEnd);
		
		HookEvent("lunge_pounce", event_immunityStart);
		HookEvent("pounce_end", event_immunityEnd);
	}
	if (StrEqual(g_sGame, "left4dead2", false))
	{
		HookEvent("jockey_ride", event_immunityStart);
		HookEvent("jockey_ride_end", event_immunityEnd);
		
		HookEvent("charger_carry_start", event_charger_carry_start);
		HookEvent("charger_carry_end", event_charger_carry_end);
		
		HookEvent("charger_pummel_start", event_charger_pummel_start);
		HookEvent("charger_pummel_end", event_charger_pummel_end);
	}
}

public void OnClientPostAdminCheck(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (!GetConVarBool(g_cvarReverseFFEnable) || !IsValidClient(attacker) || !IsValidClient(victim))
		return Plugin_Continue;
	
	if (attacker == victim || IsFakeClient(attacker) || GetClientTeam(victim) != GetClientTeam(attacker) || IsPlayerIncapped(victim))
		return Plugin_Continue;
	
	if (g_iImmuneStatus[victim] == 1 || IsPlayerIncapped(attacker) || !damage)
		return Plugin_Handled;
	
	char attackerWeapon[64];
	GetClientWeapon(attacker, attackerWeapon, sizeof(attackerWeapon));
	
	int victimDmg = RoundToNearest(damage);
	int victimDmgRemaining = victimDmg;
	int attackerHealth = GetClientHealth(attacker);
	int attackerTempHealth = GetTempHealth(attacker);
	
	// vars for LogDebug
	int victimHealth = GetClientHealth(victim);
	int victimTempHealth = GetTempHealth(victim);
	char attackerName[128];
	GetClientName(attacker, attackerName, sizeof(attackerName));
	char victimName[128];
	GetClientName(victim, victimName, sizeof(victimName));
	
	// ignore damage inflicted indirectly for example pipebomb or propanetank explosion
	if (StrEqual(g_sGame, "left4dead", false) && !IsValidClient(inflictor)) // L4D2 melee weapons have random high non-client inflictor values
		return Plugin_Continue;
	else if (StrEqual(g_sGame, "left4dead2", false) && !StrEqual(attackerWeapon, "weapon_grenade_launcher") && weapon == -1) // L4D1 always has -1 weapon
		return Plugin_Continue;

	// Punish the attacker
	if( IsPlayerAlive(attacker) && IsClientInGame(attacker) )
	{
		PrintToChatAll("'%s' (%d health & %d temphealth) attacked '%s' (%d health & %d temphealth) for %d damage", attackerName, attackerHealth, attackerTempHealth, victimName, victimHealth, victimTempHealth, victimDmg);
		LogDebug("'%s' (%d health & %d temphealth) attacked '%s' (%d health & %d temphealth) for %d damage", attackerName, attackerHealth, attackerTempHealth, victimName, victimHealth, victimTempHealth, victimDmg);

		if (attackerHealth - victimDmgRemaining >= 1)
		{
			LogDebug("DEBUG 101 - victimDmgRemaining: %d", victimDmgRemaining);
			int debugVar = attackerHealth - victimDmgRemaining;
			LogDebug("DEBUG 102 - Set %s's health to %d", attackerName, debugVar);
			
			SetEntityHealth(attacker, attackerHealth - victimDmgRemaining);
			victimDmgRemaining -= victimDmgRemaining;
			
			LogDebug("DEBUG 103 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		else if (attackerHealth - victimDmgRemaining < 1)
		{
			LogDebug("DEBUG 104 - victimDmgRemaining: %d", victimDmgRemaining);
			
			SetEntityHealth(attacker, 1);
			victimDmgRemaining -= attackerHealth - 1;
			
			LogDebug("DEBUG 105 - Set %s's health to 1", attackerName);
			LogDebug("DEBUG 106 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		
		if (attackerTempHealth != 0 && victimDmgRemaining >= 1)
		{
			if (attackerTempHealth - victimDmgRemaining >= 1)
			{
				LogDebug("DEBUG 107 - victimDmgRemaining: %d", victimDmgRemaining);
				int debugVar = attackerTempHealth - victimDmgRemaining;
				LogDebug("DEBUG 108 - Set %s's temphealth to %d", attackerName, debugVar);
				
				SetTempHealth(attacker, attackerTempHealth - victimDmgRemaining);
				victimDmgRemaining -= victimDmgRemaining;
				
				LogDebug("DEBUG 109 - victimDmgRemaining: %d", victimDmgRemaining);
			}
			else if (attackerTempHealth - victimDmgRemaining < 1)
			{
				LogDebug("DEBUG 110 - victimDmgRemaining: %d", victimDmgRemaining);
				
				SetTempHealth(attacker, 0);
				victimDmgRemaining -= attackerTempHealth;
				
				LogDebug("DEBUG 111 - Set %s's temphealth to 0", attackerName);
				LogDebug("DEBUG 112 - victimDmgRemaining: %d", victimDmgRemaining);
			}
		}
		
		if (victimDmgRemaining >= 1 && !(StrEqual(attackerWeapon, "weapon_chainsaw"))) // server crashes when incapping with chainsaw equipped
		{
			LogDebug("DEBUG 113 - victimDmgRemaining: %d", victimDmgRemaining);
			
			IncapPlayer(attacker);
			victimDmgRemaining -= 1;
			
			LogDebug("DEBUG 114 - Incapped %s", attackerName);
			LogDebug("DEBUG 115 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		
		if (victimDmgRemaining >= 1 && IsPlayerIncapped(attacker))
		{
			LogDebug("DEBUG 116 - victimDmgRemaining: %d", victimDmgRemaining);
			int debugVar = 300 - victimDmgRemaining;
			LogDebug("DEBUG 117 - Set %s's health to %d", attackerName, debugVar);
			
			SetEntityHealth(attacker, 300 - victimDmgRemaining);
			victimDmgRemaining -= victimDmgRemaining;
			
			LogDebug("DEBUG 118 - victimDmgRemaining: %d", victimDmgRemaining);
		}
	}
	
	// Announce damage
	if (g_bFFActive[attacker])  //If the player is already friendly firing teammates, resets the announce timer and adds to the damage
	{
		Handle pack;
		g_iDamageCache[attacker][victim] += victimDmg;
		KillTimer(g_hFFTimer[attacker]);
		g_hFFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
	}
	else //If it's the first friendly fire by that player, it will start the announce timer and store the damage done.
	{
		g_iDamageCache[attacker][victim] = victimDmg;
		Handle pack;
		g_bFFActive[attacker] = true;
		g_hFFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
		for (int i = 1; i < 19; i++)
		{
			if (i != attacker && i != victim)
			{
				g_iDamageCache[attacker][i] = 0;
			}
		}
	}
	
	return Plugin_Handled;
}

public Action AnnounceFF(Handle timer, Handle pack) { //Called if the attacker did not friendly fire recently, and announces all FF they did
	char victim[128];
	char attacker[128];
	ResetPack(pack);
	int attackerc = ReadPackCell(pack);
	g_bFFActive[attackerc] = false;
	if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
		GetClientName(attackerc, attacker, sizeof(attacker));
	else
		attacker = "Disconnected Player";
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (g_iDamageCache[attackerc][i] != 0)
		{
			if (IsClientInGame(i) && IsClientConnected(i))
			{
				GetClientName(i, victim, sizeof(victim));
				
				PrintToChatAll("Reversed %d damage %s did to %s",g_iDamageCache[attackerc][i],attacker,victim);
					
				g_iDamageCache[attackerc][i] = 0;
			}
		}
	}
}

public Action event_player_bot_replace(Handle event, const char[] name, bool dontBroadcast) {
	int playerId = GetClientOfUserId(GetEventInt(event, "player"));
	
	if (StrEqual(g_sGame, "left4dead", false) && L4D_IsSurvivorAffectedBySI(playerId))
		g_iImmuneStatus[playerId] = 1;
	else if (StrEqual(g_sGame, "left4dead2", false) && L4D2_IsSurvivorAffectedBySI(playerId))
	{
		g_iImmuneStatus[playerId] = 1;
		
		if (GetEntPropEnt(playerId, Prop_Send, "m_carryAttacker") > 0)
			g_iCarryStatus[playerId] = 1;
		if (GetEntPropEnt(playerId, Prop_Send, "m_pummelAttacker") > 0)
			g_iPummelStatus[playerId] = 1;
	}
}

public Action event_bot_player_replace(Handle event, const char[] name, bool dontBroadcast) {
	int playerId = GetClientOfUserId(GetEventInt(event, "player"));
	
	if (StrEqual(g_sGame, "left4dead", false) && L4D_IsSurvivorAffectedBySI(playerId))
		g_iImmuneStatus[playerId] = 0;
	else if (StrEqual(g_sGame, "left4dead2", false) && L4D2_IsSurvivorAffectedBySI(playerId))
	{
		g_iImmuneStatus[playerId] = 0;
		g_iCarryStatus[playerId] = 0;
		g_iPummelStatus[playerId] = 0;
	}
}

public Action event_immunityStart(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;

	if (g_iDebugMode) PrintToChatAll("event_immunityStart - g_iImmuneStatus 1");
	g_iImmuneStatus[client] = 1;
}

public Action event_immunityEnd(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	if (g_iDebugMode) PrintToChatAll("event_immunityEnd - starting Timer_immunityEnd");
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action event_charger_carry_start(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	if (g_iDebugMode) PrintToChatAll("event_charger_carry_start");
	g_iCarryStatus[client] = 1;
	g_iImmuneStatus[client] = 1;
}

public Action event_charger_carry_end(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	if (g_iDebugMode) PrintToChatAll("event_charger_carry_end - starting Timer_immunityEnd");
	g_iCarryStatus[client] = 0;
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action event_charger_pummel_start(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	if (g_iDebugMode) PrintToChatAll("event_charger_pummel_start");
	g_iPummelStatus[client] = 1;
	g_iImmuneStatus[client] = 1;
}

public Action event_charger_pummel_end(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	if (g_iDebugMode) PrintToChatAll("event_charger_pummel_end - starting Timer_immunityEnd");
	g_iPummelStatus[client] = 0;
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action Timer_immunityEnd(Handle timer, any client) {
	if (g_iCarryStatus[client] == 1 || g_iPummelStatus[client] == 1) // do not remove immunity if victim is being carried or pummeled by charger
	{
		// PrintToChatAll("Timer_immunityEnd: survivor is being pummeled or carried");
		return;
	}
	
	if (g_iDebugMode) PrintToChatAll("Timer_immunityEnd - g_iImmuneStatus 0");
	g_iImmuneStatus[client] = 0;
}

static void LogDebug(const char[] format, any:...) {
	if (!g_iDebugLog)
		return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
	Handle file;
	char FileName[256];
	char sTime[256];
	FormatTime(sTime, sizeof(sTime), "%Y%m%d");
	BuildPath(Path_SM, FileName, sizeof(FileName), "logs/reverse_ff_debug_%s.log", sTime);
	file = OpenFile(FileName, "a+");
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y - %H:%M:%S");
	WriteFileLine(file, "%s: %s", sTime, buffer);
	FlushFile(file);
	CloseHandle(file);
}