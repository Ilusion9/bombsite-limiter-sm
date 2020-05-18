#include <sourcemod>
#include <sdktools> 
#include <cstrike> 
#include <sourcecolors> 
#pragma newdecls required 

public Plugin myinfo =
{
	name = "Bombsite Limiter",
	author = "Ilusion9",
	description = "Disable specified bombsites if there are fewer CTs than their accepted limit",
	version = "2.0",
	url = "https://github.com/Ilusion9/"
};

enum struct SiteInfo
{
	int entityId;
	char radarLetter;
	char Letter;
	int limitCTs;
}

SiteInfo g_BombSites[16];
int g_NumOfBombSites;

ConVar g_Cvar_GraceTime;
ConVar g_Cvar_FreezeTime;
EngineVersion g_EngineVersion;
Handle g_Timer_FreezeEnd;

bool g_IsMapConfigLoaded;

public void OnPluginStart() 
{
	g_EngineVersion = GetEngineVersion();
	if (g_EngineVersion != Engine_CSGO && g_EngineVersion != Engine_CSS)
	{
		SetFailState("This plugin is designed only for CS:GO and CS:S.");
	}
	
	LoadTranslations("bombsite_limiter.phrases");
	HookEvent("round_start", Event_RoundStart);
	
	g_Cvar_GraceTime = FindConVar("mp_join_grace_time");
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnMapStart()
{
	g_IsMapConfigLoaded = false;
	g_NumOfBombSites = 0;
	int entity = -1;

	while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
	{
		g_BombSites[g_NumOfBombSites].entityId = entity;
		
		g_BombSites[g_NumOfBombSites].radarLetter = 0;
		g_BombSites[g_NumOfBombSites].Letter = 0;
		g_BombSites[g_NumOfBombSites].limitCTs = 0;
		
		g_NumOfBombSites++;
	}
}

public void OnMapEnd()
{
	g_IsMapConfigLoaded = false;
	delete g_Timer_FreezeEnd;
}

public void OnClientPutInServer()
{
	if (!g_IsMapConfigLoaded)
	{
		LoadMapConfiguration();
		g_IsMapConfigLoaded = true;
	}
}

void LoadMapConfiguration()
{
	GetRadarLetters();
	
	char path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("Bombsites"); 
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_limiter.cfg");
	
	if (!kv.ImportFromFile(path)) 
	{
		delete kv;
		LogError("The configuration file could not be read.");
		return;
	}
	
	int limitCTs;
	char currentMap[PLATFORM_MAX_PATH], radarLetter[3], letter[3];
	GetCurrentMap(currentMap, sizeof(currentMap));
	
	if (kv.JumpToKey(currentMap))
	{		
		if (kv.GotoFirstSubKey(false))
		{
			do {
				kv.GetString("radar_letter", radarLetter, sizeof(radarLetter), "");				
				kv.GetString("letter", letter, sizeof(letter), "");				
				limitCTs = kv.GetNum("ct_limit", 0);
				
				for (int i = 0; i < g_NumOfBombSites; i++)
				{					
					if (g_BombSites[i].radarLetter == radarLetter[0])
					{						
						g_BombSites[i].Letter = letter[0];
						g_BombSites[i].limitCTs = limitCTs;
						break;
					}
				}
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	delete kv;
	
	// Players should not be spawned after the round starts
	if (g_Cvar_GraceTime)
	{
		g_Cvar_GraceTime.IntValue = 0;
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (!g_NumOfBombSites || IsWarmupPeriod())
	{
		return;
	}
	
	float freezeTime = g_Cvar_FreezeTime ? g_Cvar_FreezeTime.FloatValue + 1.0 : 1.0;
	g_Timer_FreezeEnd = CreateTimer(freezeTime, Timer_HandleFreezeEnd);
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	bool hasRestrictions = false;
	int numOfCTs = GetCounterTerroristsCount();
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		AcceptEntityInput(g_BombSites[i].entityId, "Enable");
		
		if (!g_BombSites[i].limitCTs || !g_BombSites[i].Letter)
		{
			continue;
		}
		
		if (numOfCTs < g_BombSites[i].limitCTs)
		{
			hasRestrictions = true;
			AcceptEntityInput(g_BombSites[i].entityId, "Disable");
			CPrintToChatAll("> %t", "Bombsite Restricted with Reason", g_BombSites[i].Letter, g_BombSites[i].limitCTs);
		}
	}
	
	if (!hasRestrictions)
	{
		CPrintToChatAll("> %t", "No Bombsites Restricted");
	}
	
	g_Timer_FreezeEnd = null;
}

bool IsWarmupPeriod()
{
	if (g_EngineVersion != Engine_CSGO)
	{
		return false;
	}
	
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

void GetRadarLetters()
{
	float vecCenterA[3], vecCenterB[3], vecMins[3], vecMaxs[3];
	int ent = FindEntityByClassname(-1, "cs_player_manager");
    
	if (ent != -1)
	{
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", vecCenterA);
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", vecCenterB);
	}
    
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		GetEntPropVector(g_BombSites[i].entityId, Prop_Send, "m_vecMins", vecMins);
		GetEntPropVector(g_BombSites[i].entityId, Prop_Send, "m_vecMaxs", vecMaxs);
        
		if (IsVecBetween(vecCenterA, vecMins, vecMaxs))
		{
			g_BombSites[i].radarLetter = 'A';
		}
		
		else if (IsVecBetween(vecCenterB, vecMins, vecMaxs))
		{
			g_BombSites[i].radarLetter = 'B';
		}
		
		else
		{
			g_BombSites[i].radarLetter = 'C';
		}
	}
}

bool IsVecBetween(const float vecVector[3], const float vecMin[3], const float vecMax[3]) 
{
	for (int i = 0; i < 3; i++)
	{
		if (vecVector[i] < vecMin[i] || vecVector[i] > vecMax[i])
		{
			return false;
		}
	}
	
	return true;
}

int GetCounterTerroristsCount()
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
