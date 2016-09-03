/* Plugin Template generated by Pawn Studio */

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "L4D FF Announce Plugin",
	author = "Frustian",
	description = "Adds Friendly Fire Announcements",
	version = "1.4",
	url = ""
}
//cvar handles
Handle FFenabled;
Handle AnnounceType
//Various global variables
int DamageCache[MAXPLAYERS+1][MAXPLAYERS+1]; //Used to temporarily store Friendly Fire Damage between teammates
Handle FFTimer[MAXPLAYERS+1]; //Used to be able to disable the FF timer when they do more FF
bool FFActive[MAXPLAYERS+1]; //Stores whether players are in a state of friendly firing teammates
Handle directorready;
public void OnPluginStart()
{
	CreateConVar("l4d_ff_announce_version", "1.4", "FF announce Version",FCVAR_SPONLY|FCVAR_NOTIFY);
	FFenabled = CreateConVar("l4d_ff_announce_enable", "1", "Enable Announcing Friendly Fire",FCVAR_SPONLY|FCVAR_NOTIFY);
	AnnounceType = CreateConVar("l4d_ff_announce_type", "1", "Changes how ff announce displays FF damage (1:In chat; 2: In Hint Box; 3: In center text)",FCVAR_SPONLY);
	HookEvent("player_hurt_concise", Event_HurtConcise, EventHookMode_Post);
	directorready = FindConVar("director_ready_duration");
}

public Action Event_HurtConcise(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetEventInt(event, "attackerentid");
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	// if (!GetConVarInt(FFenabled) || !GetConVarInt(directorready) || attacker > MaxClients || attacker < 1 || !IsClientConnected(attacker) || !IsClientInGame(attacker) || IsFakeClient(attacker) || GetClientTeam(attacker) != 2 || !IsClientInGame(victim) || !IsClientConnected(victim) || GetClientTeam(victim) != 2)
		// return;  //if director_ready_duration is 0, it usually means that the game is in a ready up state like downtown1's ready up mod.  This allows me to disable the FF messages in ready up.
	int damage = GetEventInt(event, "dmg_health");
	if (FFActive[attacker])  //If the player is already friendly firing teammates, resets the announce timer and adds to the damage
	{
		Handle pack;
		DamageCache[attacker][victim] += damage;
		KillTimer(FFTimer[attacker]);
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
	}
	else //If it's the first friendly fire by that player, it will start the announce timer and store the damage done.
	{
		DamageCache[attacker][victim] = damage;
		Handle pack;
		FFActive[attacker] = true;
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
		for (int i = 1; i < 19; i++)
		{
			if (i != attacker && i != victim)
			{
				DamageCache[attacker][i] = 0;
			}
		}
	}
}
public Action AnnounceFF(Handle timer, Handle pack) //Called if the attacker did not friendly fire recently, and announces all FF they did
{
	char victim[128];
	char attacker[128];
	ResetPack(pack);
	int attackerc = ReadPackCell(pack);
	FFActive[attackerc] = false;
	if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
		GetClientName(attackerc, attacker, sizeof(attacker));
	else
		attacker = "Disconnected Player";
	for (int i = 1; i < MaxClients; i++)
	{
		if (DamageCache[attackerc][i] != 0 && attackerc != i)
		{
			if (IsClientInGame(i) && IsClientConnected(i))
			{
				GetClientName(i, victim, sizeof(victim));
				switch(GetConVarInt(AnnounceType))
				{
					case 1:
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
							PrintToChat(attackerc, "[SM] You did %d friendly fire damage to %s",DamageCache[attackerc][i],victim);
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
							PrintToChat(i, "[SM] %s did %d friendly fire damage to you",attacker,DamageCache[attackerc][i]);
					}
					case 2:
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
							PrintHintText(attackerc, "You did %d friendly fire damage to %s",DamageCache[attackerc][i],victim);
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
							PrintHintText(i, "%s did %d friendly fire damage to you",attacker,DamageCache[attackerc][i]);
					}
					case 3:
					{
						if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
							PrintCenterText(attackerc, "You did %d friendly fire damage to %s",DamageCache[attackerc][i],victim);
						if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
							PrintCenterText(i, "%s did %d friendly fire damage to you",attacker,DamageCache[attackerc][i]);
					}
				}
			}
			DamageCache[attackerc][i] = 0;
		}
	}
}