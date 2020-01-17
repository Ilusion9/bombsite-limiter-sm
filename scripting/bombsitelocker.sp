#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Bombsite Locker",
	author = "Ilusion9",
	description = "Disable specified bombsites if there are fewer CTs than their accepted limit",
	version = "3.0",
	url = "https://github.com/Ilusion9/"
};

#define MAX_BOMBSITES	10
enum struct SiteInfo
{
	int entityId;
	int hammerId;
	char letter;
	int limit;
}

ConVar g_Cvar_FreezeTime;
Handle g_Timer_FreezeEnd;

SiteInfo g_Bombsites[MAX_BOMBSITES];
int g_NumOfBombsites;

bool g_IsChangingSettings[MAXPLAYERS + 1];
int g_SelectedBombsite[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("bombsitelocker.phrases");
	RegAdminCmd("sm_bombsites", Command_Bombsites, ADMFLAG_RCON);
	
	HookEvent("round_start", Event_RoundStart);	
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_NumOfBombsites = 0;
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
	{
		g_Bombsites[g_NumOfBombsites].entityId = ent;
		g_Bombsites[g_NumOfBombsites].hammerId = GetEntProp(ent, Prop_Data, "m_iHammerID");
		g_Bombsites[g_NumOfBombsites].letter = 0;
		g_Bombsites[g_NumOfBombsites].limit = 0;
		
		g_NumOfBombsites++;
	}
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	
	if (!kv.ImportFromFile(path))
	{
		delete kv;
		return;
	}
	
	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			char buffer[65];
			kv.GetSectionName(buffer, sizeof(buffer));
			int hammerId = StringToInt(buffer);
			
			for (int i = 0; i < g_NumOfBombsites; i++)
			{
				if (g_Bombsites[i].hammerId == hammerId)
				{
					char letter[3];
					kv.GetString("letter", letter, sizeof(letter), "\n");
					g_Bombsites[i].letter = letter[0];
					g_Bombsites[i].limit = kv.GetNum("ct_limit", 0);
					break;
				}
			}
			
		} while (kv.GotoNextKey(false));
	}
	
	delete kv;
	FindConVar("mp_join_grace_time").SetInt(0);
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker");
	if (!DirExists(path))
	{
		CreateDirectory(path, 0777);
	}
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	kv.ImportFromFile(path);
	
	for (int i = 0; i < g_NumOfBombsites; i++)
	{
		char key[65];
		Format(key, sizeof(key), "%d", g_Bombsites[i].hammerId);
		
		if (!g_Bombsites[i].letter || !g_Bombsites[i].limit)
		{
			if (kv.JumpToKey(key))
			{
				kv.DeleteThis();
				kv.GoBack();
			}
			
			continue;
		}
		
		kv.JumpToKey(key, true);
		char letter[3];
		Format(letter, sizeof(letter), "%c", g_Bombsites[i].letter);
		
		kv.SetString("letter", letter);
		kv.SetNum("ct_limit", g_Bombsites[i].limit);		
		kv.GoBack();
	}
	
	kv.ExportToFile(path);
	delete kv;
}

public void OnClientConnected(int client)
{
	g_IsChangingSettings[client] = false;
}

public void OnClientDisconnect_Post(int client)
{
	g_IsChangingSettings[client] = false;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (IsWarmupPeriod())
	{
		return;
	}
	
	g_Timer_FreezeEnd = CreateTimer(g_Cvar_FreezeTime.FloatValue + 1.0, Timer_HandleFreezeEnd);
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	int CTs = GetCounterTerroristsCount();
	if (CTs > 0)
	{
		for (int i = 0; i < g_NumOfBombsites; i++)
		{
			AcceptEntityInput(g_Bombsites[i].entityId, "Enable");
			
			if (!g_Bombsites[i].limit || !g_Bombsites[i].letter)
			{
				continue;
			}
			
			if (CTs < g_Bombsites[i].limit)
			{
				AcceptEntityInput(g_Bombsites[i].entityId, "Disable");
				PrintToChatAll("%t", "Bombsite Disabled Reason", g_Bombsites[i].letter, g_Bombsites[i].limit);
			}
		}
	}
	
	g_Timer_FreezeEnd = null;
}

public Action Command_Bombsites(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!g_NumOfBombsites)
	{
		ReplyToCommand(client, "[SM] This map has no bomb sites!");
		return Plugin_Handled;
	}
	
	ShowBombSitesMenu(client);
	return Plugin_Handled;
}

void ShowBombSitesMenu(int client)
{
	Menu menu = new Menu(Menu_BombSitesHandler);
	menu.SetTitle("Bombsite Locker");

	for (int i = 0; i < g_NumOfBombsites; i++)
	{
		char buffer[65];
		Format(buffer, sizeof(buffer), "Bombsite %d", i + 1);
		menu.AddItem("", buffer);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_BombSitesHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	
	if (action != MenuAction_Select)
	{
		return 0;
	}
	
	g_SelectedBombsite[param1] = param2;
	ShowOptionsMenu(param1);
	
	return 0;
}

void ShowOptionsMenu(int client)
{
	int option = g_SelectedBombsite[client];
	Menu menu = new Menu(Menu_OptionsHandler);
	
	menu.SetTitle("Bombsite %d", option + 1);
	menu.AddItem("", "Teleport to");

	char buffer[65];
	if (g_Bombsites[option].limit && g_Bombsites[option].letter)
	{
		Format(buffer, sizeof(buffer), "Change settings [%c - %d]", g_Bombsites[option].letter, g_Bombsites[option].limit);
	}
	else
	{
		Format(buffer, sizeof(buffer), "Create settings");
	}
	menu.AddItem("", buffer);
	
	if (g_Bombsites[option].limit && g_Bombsites[option].letter)
	{
		menu.AddItem("", "Remove settings");
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_OptionsHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	
	if (action == MenuAction_Cancel)
	{
		if (g_IsChangingSettings[param1])
		{
			PrintToChat(param1, "[SM] The action to change this bombsite settings was canceled!");
			g_IsChangingSettings[param1] = false;
		}
		
		if (param2 == MenuCancel_ExitBack)
		{
			ShowBombSitesMenu(param1);
		}
	}
	
	if (action != MenuAction_Select)
	{
		return 0;
	}
	
	switch (param2)
	{
		case 0:
		{
			int option = g_SelectedBombsite[param1];
			int ent = g_Bombsites[option].entityId;
			
			float origin[3], vecMins[3], vecMaxs[3];
			GetEntPropVector(ent, Prop_Send, "m_vecMins", vecMins); 
			GetEntPropVector(ent, Prop_Send, "m_vecMaxs", vecMaxs);
			
			GetMiddleOfABox(vecMins, vecMaxs, origin);
			TeleportEntity(param1, origin, NULL_VECTOR, NULL_VECTOR);
			
			ShowOptionsMenu(param1);
		}
		
		case 1:
		{
			g_IsChangingSettings[param1] = true;
			PrintToChat(param1, "[SM] Type in chat the letter and the CT limit for this bombsite! Example: 'B 5'");
			PrintToChat(param1, "[SM] Type 'cancel' to abort this action!");
			ShowOptionsMenu(param1);
		}
		
		case 2:
		{
			if (g_IsChangingSettings[param1])
			{
				PrintToChat(param1, "[SM] The action to change this bombsite settings was canceled!");
				g_IsChangingSettings[param1] = false;
			}

			int option = g_SelectedBombsite[param1];
			g_Bombsites[option].letter = 0;
			g_Bombsites[option].limit = 0;
			ShowOptionsMenu(param1);
		}
	}
	
	return 0;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (g_IsChangingSettings[client])
	{
		if (StrEqual(sArgs, "cancel", false))
		{
			g_IsChangingSettings[client] = false;
			PrintToChat(client, "[SM] The action to change this bombsite settings was canceled!");
			return Plugin_Handled;
		}
		
		char letter = sArgs[0];
		int index = g_SelectedBombsite[client];
		
		if (letter < 'A' || letter > 'Z')
		{
			PrintToChat(client, "[SM] The letter must be between 'A' and 'Z'. Please type again!");
			PrintToChat(client, "[SM] Type 'cancel' to abort this action!");
			return Plugin_Handled;
		}
		
		char buffer[65];
		Format(buffer, sizeof(buffer), "%s", sArgs);
		ReplaceString(buffer, sizeof(buffer), " ", "");
		
		int limit;
		if (!StringToIntEx(sArgs[1], limit) || limit < 1)
		{
			PrintToChat(client, "[SM] Invalid limit of CTs specified!");
			PrintToChat(client, "[SM] Type 'cancel' to abort this action!");
			return Plugin_Handled;
		}
		
		g_IsChangingSettings[client] = false;
		g_Bombsites[index].letter = letter;
		g_Bombsites[index].limit = limit;

		PrintToChat(client, "[SM] The bombsite settings were changed! (%c - %d)", letter, limit);
		
		ShowOptionsMenu(client);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

int GetCounterTerroristsCount()
{
	int num = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}

	return num;
}

bool IsWarmupPeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

/* From devzones plugin */
void GetMiddleOfABox(const float vec1[3], const float vec2[3], float buffer[3])
{
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, buffer);
}
