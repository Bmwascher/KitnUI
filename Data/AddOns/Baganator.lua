-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Baganator.lua                                               ║
-- ║  Purpose: Profile data: Baganator settings + the raw category ║
-- ║           export string.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- Written into a named BAGANATOR_CONFIG.Profiles entry on import and activated
-- for this character through BAGANATOR_CURRENT_PROFILE, which is a per-character
-- SavedVariable. Applied only on an explicit install or load action, never on
-- PLAYER_LOGIN, so changes the user makes inside the profile survive a reload.
--
-- `categoriesJSON` is the raw export string from Baganator's
-- Customise > Categories > Export button. Setup.lua decodes it with
-- C_EncodingUtil.DeserializeJSON and converts the array fields (items, pets,
-- hideIn) into the hashmap form Baganator stores internally.
ns.data.Baganator = {
    bag_view_type = "category",
    bank_view_type = "category",
    seen_welcome = 1,
    categoriesJSON = [[{"categories":[{"source":"1","name":"Enchants","search":"#item enhancement"},{"source":"3","name":"Warbound","search":""},{"source":"2","name":"Utility","search":"#utility"},{"source":"5","name":"Flask/Pot/Oil/Rune","search":"#flasks phials|#potions"},{"source":"4","name":"Transform","search":"#transform"}],"version":2,"sections":{"1":{"name":"Essentials"},"4":{"name":"CRAFTING"},"3":{"name":"Catch-All"},"2":{"name":"Gear"}},"addon":"Baganator","order":["default_auto_recents","----","_1","4","5","default_food","2","default_consumable","__end","_2","1","default_gem","default_auto_equipment_sets","default_weapon","default_armor","3","__end","_3","default_keystone","default_questitem","default_miscellaneous","default_key","default_battlepet","default_container","default_housing","__end","_4","default_reagent","default_tradegoods","default_recipe","__end","default_other","----","default_junk","default_special_empty"],"modifications":[{"items":[224292,219522,225767,235053],"source":"default_questitem","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_armor","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_junk","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_housing","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_weapon","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_other","priority":-1,"hideIn":[]},{"items":[226147,151134,235897,220520],"source":"default_miscellaneous","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_battlepet","priority":-1,"hideIn":[]},{"items":[114943,87216],"source":"default_reagent","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"items":[242747,222776,268679],"source":"default_food","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"items":[257535,232386,226505,210436,248410,213777],"source":"default_gem","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"3","priority":0,"hideIn":[]},{"items":[63352,158380,132514,109076,219905,226120,63207,49040,63206,188152,234389,63353,52251,64399,111820,221955,65274,221949,226132,132516,65360],"source":"2","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"items":[243734,259085],"source":"5","showGroupPrefix":true,"priority":0,"hideIn":[]},{"items":[104316,249708,153597,102463,8529,112384,128510,193031,224353,224363,224367,224365,224366,124640,224361,224356,6657,224348],"source":"4","showGroupPrefix":true,"priority":0,"hideIn":[]},{"showGroupPrefix":true,"source":"default_consumable","priority":-1,"hideIn":[]},{"items":[109253],"source":"default_tradegoods","showGroupPrefix":true,"priority":-1,"hideIn":[]},{"source":"default_profession","hideIn":[]},{"showGroupPrefix":true,"source":"default_keystone","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_container","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_auto_equipment_sets","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_potion","priority":3,"hideIn":[]},{"showGroupPrefix":true,"source":"1","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_recipe","priority":-1,"hideIn":[]},{"showGroupPrefix":true,"source":"default_key","priority":-1,"hideIn":[]}],"hidden":["3","default_special_empty"]}]],
}
