#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod>
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Limiter",
    author = "Ilusion9",
    description = "Disable bombsite A or B if there are fewer CTs than the accepted limit",
    version = "2.1",
    url = "https://github.com/Ilusion9/"
};

enum
{
	SITE_A = 65,
	SITE_B
};

ConVar g_Cvar_FreezeTime;
Handle g_Timer_FreezeEnd;

int g_iSiteLimit;
int g_iSiteToLock;

public void OnPluginStart() 
{
	LoadTranslations("bombsites.phrases");

	HookEvent("round_start", Event_RoundStart);	
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_iSiteLimit = 0;
	g_iSiteToLock = 0;
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	if (!kv.ImportFromFile(path)) {
		SetFailState("The configuration file could not be read.");
	}
	
	if (kv.JumpToKey(map)) 
	{
		char key[64];
		kv.GetString("site_locked", key, sizeof(key));
		
		if (StrEqual(key, "A", false))
		{
			g_iSiteToLock = SITE_A;
		}
		
		else if (StrEqual(key, "B", false))
		{
			g_iSiteToLock = SITE_B;
		}
		
		g_iSiteLimit = kv.GetNum("ct_limit", 0);
	}
	
	delete kv;
	
	if (g_iSiteToLock)
	{
		/* Players should not be spawned after the freeze time ends */
		FindConVar("mp_join_grace_time").IntValue = 0;
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	if (GameRules_GetProp("m_bWarmupPeriod")) {
		return;
	}
	
	if (g_iSiteToLock) 
	{
		delete g_Timer_FreezeEnd;
		g_Timer_FreezeEnd = CreateTimer(g_Cvar_FreezeTime.FloatValue + 1.0, Timer_HandleFreezeEnd);
	}
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	int siteA = -1, siteB = -1;
	int ent = FindEntityByClassname(-1, "cs_player_manager");

	if (ent != -1)
	{
		/* Get bombsites coordinates from players radar */
		float bombsiteCenterA[3], bombsiteCenterB[3];
		
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", bombsiteCenterA); 
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", bombsiteCenterB);
		
		/* Find which site is A and which is B by checking those coordinates */
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
		{
			float vecMins[3], vecMaxs[3];
			
			GetEntPropVector(ent, Prop_Send, "m_vecMins", vecMins); 
			GetEntPropVector(ent, Prop_Send, "m_vecMaxs", vecMaxs);
			
			if (IsVecBetween(bombsiteCenterA, vecMins, vecMaxs))
			{
				siteA = ent; 
			}
			
			else if (IsVecBetween(bombsiteCenterB, vecMins, vecMaxs))
			{
				siteB = ent;
			}
			
			AcceptEntityInput(ent, "Enable");
		}
	}
			
	if (siteA != -1 && siteB != -1)
	{
		if (GetCounterTerroristsCount() < g_iSiteLimit)
		{
			AcceptEntityInput(g_iSiteToLock != SITE_A ? siteB : siteA, "Disable");	

			PrintToChatAll("%t", "Bombsite Disabled Reason", g_iSiteToLock, g_iSiteLimit);
			PrintCenterTextAll("%t", "Bombsite Disabled", g_iSiteToLock);
		}
	}
	
	g_Timer_FreezeEnd = null;
	return Plugin_Continue;
}

stock bool IsVecBetween(const float vec[3], const float mins[3], const float maxs[3]) 
{
	for (int i = 0; i < 3; i++)
	{
		if (vec[i] < mins[i] || vec[i] > maxs[i])
		{
			return false;
		}
	}
	
	return true;
}

stock int GetCounterTerroristsCount()
{
	int num;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}

	return num;
}
