#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Reverse Friendly Fire",
	author = "Me",
	description = "Reverses Friendly Fire",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnClientPostAdminCheck(int client)
{
	// PrintToChatAll("OnClientPostAdminCheck()")
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// /*
public void OnMapStart()
{
	// PrintToChatAll("OnMapStart()")
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
}
// */ 

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	int VictimId = victim;
	int AttackerId = attacker;
	int VictimDmg = RoundToNearest(damage);

	/*
	PrintToServer("victim: %d", victim)
	PrintToServer("attacker: %d", attacker)
	PrintToServer("inflictor: %d", inflictor)
	PrintToServer("damagetype: %d", damagetype)
	PrintToServer("weapon: %d", weapon)
	PrintToServer("damageForce: %f", damageForce)
	PrintToServer("damagePosition: %f", damagePosition)
	*/
	
	if ( (!IsValidEntity(VictimId)) || (!IsValidEntity(AttackerId)) ) // are victim & attacker invalid entities?
	{
		// PrintToChatAll("invalid VictimId (%d) or AttackerId (%d)", VictimId, AttackerId)
		return Plugin_Continue
	}

	if ( (GetClientTeam(VictimId) != GetClientTeam(AttackerId)) ) // are victim & attacker not on the same team?
	{
		// PrintToChatAll("victim is not on the same team as attacker")
		return Plugin_Continue
	}

	if (AttackerId == VictimId) // is damage inflicted to self?
	{
		// PrintToChatAll("damage inflicted to self")
		return Plugin_Continue
	}

	if (IsFakeClient(VictimId)) // is victim a bot?
	{
		// PrintToChatAll("damage inflicted to bot")
		return Plugin_Continue
	}
	
	// damage inflicted indirectly eg: pipebomb or propanetank explosion
	char sGame[256];
	GetGameFolderName(sGame, sizeof(sGame));
	if (StrEqual(sGame, "left4dead", false))
	{
		if ( !IsValidClient(inflictor) )	// L4D2 melee weapons have random high non-client values
		{
			// PrintToChatAll("l4d1: damage inflicted indirectly")
			return Plugin_Continue
		}
	}
	else if (StrEqual(sGame, "left4dead2", false))
	{
		if (weapon == -1) // L4D1 always has -1 weapon
		{
			// PrintToChatAll("l4d2: damage inflicted indirectly")
			return Plugin_Continue
		}
	}
	
	if (CheckCommandAccess(AttackerId, "root_admin", ADMFLAG_ROOT, true)) // if user is root admin
	{
		// PrintToChatAll("damage inflicted by root admin")
		return Plugin_Continue
	}
	
	// if (GetUserAdmin(AttackerId) != INVALID_ADMIN_ID) // if user is an admin
	// {
		// PrintToChatAll("damage inflicted by an admin")
		// return Plugin_Continue
	// }

	// Punish the attacker
	if( IsPlayerAlive(AttackerId) && IsClientInGame(AttackerId) )
	{
		int AttackerHealth = GetClientHealth(AttackerId);
		int AttackerTempHealth = GetTempHealth(AttackerId);

		if( AttackerHealth > 1 )
		{
			if ((AttackerHealth - VictimDmg) > 1)
				SetEntityHealth(AttackerId, AttackerHealth - VictimDmg);
			else
				SetEntityHealth(AttackerId, 1)
		}
		else if (AttackerTempHealth > 0)
		{
			if ((AttackerTempHealth - VictimDmg) > 0)
				SetTempHealth(AttackerId, (AttackerTempHealth - VictimDmg + 1));
			else
				SetTempHealth(AttackerId, 0)
		}
		else
		{
			IncapPlayer(AttackerId)
		}
	}

	return Plugin_Handled; // do not apply damage to victim
}
int GetTempHealth(int client)
{
	float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	float time = (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime"));
	float TempHealth = buffer - (time * decay)
	if (TempHealth < 0) return 0;
	else return RoundToFloor(TempHealth);
}

int SetTempHealth(int client, int hp)
{
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
	float TempHealthFloat = hp * 1.0 //prevent tag mismatch
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", TempHealthFloat);
}

void IncapPlayer(int target)
{
	if(IsValidEntity(target))
	{
		int iDmgEntity = CreateEntityByName("point_hurt");
		SetEntityHealth(target, 1);
		DispatchKeyValue(target, "targetname", "bm_target");
		DispatchKeyValue(iDmgEntity, "DamageTarget", "bm_target");
		DispatchKeyValue(iDmgEntity, "Damage", "100");
		DispatchKeyValue(iDmgEntity, "DamageType", "0");
		DispatchSpawn(iDmgEntity);
		AcceptEntityInput(iDmgEntity, "Hurt", target);
		DispatchKeyValue(target, "targetname", "bm_targetoff");
		RemoveEdict(iDmgEntity);
	}
}

bool IsValidClient(int client) 
{
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
        return false; 
     
    return true; 
} 