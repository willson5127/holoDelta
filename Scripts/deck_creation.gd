#The deckbuilder
#Most of the magic happens in two TabContainers - PossibleCards and YourStuff
#PossibleCards has 4 tabs - Oshi, Holomem, Support, and Cheer
#These each contain a ScrollContainer of a list of cards to add to your deck
#	and a smattering of Buttons/LineEdits for filters
#YourStuff has 3 tabs - Deck, Analytics, and Sleeves
#Deck shows what the deck you're bulding currently looks like
#Analytics has some stats of the deck
#Sleeves has 3 SleeveSelects for main deck, cheer deck, and oshi

extends Node2D

#region Variables

const card = preload("res://Scenes/card.tscn")
const default_sleeve = preload("res://holoBack.png")
const default_cheer_sleeve = preload("res://cheerBack.png")
const default_oshi_sleeve = preload("res://cheerBack.png")

var all_cards = [] #Holds all cards, both in the right panel and your deck

#Contains specific types of cards for sorting/filtering purposes
var oshi_cards : Array
var holomem_cards : Array
var support_cards : Array

#A list of cards [card number, art index] that we've already put in the list
#Added for proxy purposes, so we only see one version
var cardsFound = []

#The actual deck choices you've made
var oshiCard #Actually the card object itself... for some reason
var in_deck_dictionary = {}
var sleeve = default_sleeve
var cheer_sleeve = default_cheer_sleeve
var oshi_sleeve = default_oshi_sleeve

#Variables for analytics
var total_main = 0
var total_cheer = 0
var total_debut = 0
var total_1st = 0
var total_2nd = 0
var total_spot = 0
var total_color = {}
var total_support = 0

var json = JSON.new()

#Constants filled up at runtime. So the name select isn't giving you options that aren't in the game
var oshi_colors = []
var oshi_names = []
var holomem_colors = []
var holomem_names = []
var holomem_tags = []
var support_types = []

#Filter Buttons/LineEdits
@onready var oshi_name_select = $CanvasLayer/PossibleCards/Oshi/NameSelect
@onready var oshi_color_select = $CanvasLayer/PossibleCards/Oshi/ColorSelect
@onready var oshi_search = $CanvasLayer/PossibleCards/Oshi/Search

@onready var holomem_name_select = $CanvasLayer/PossibleCards/Holomem/NameSelect
@onready var holomem_color_select = $CanvasLayer/PossibleCards/Holomem/ColorSelect
@onready var holomem_level_select = $CanvasLayer/PossibleCards/Holomem/LevelSelect
@onready var holomem_buzz_select = $CanvasLayer/PossibleCards/Holomem/BuzzSelect
@onready var holomem_tag_select = $CanvasLayer/PossibleCards/Holomem/TagSelect
@onready var holomem_search = $CanvasLayer/PossibleCards/Holomem/Search

@onready var support_type_select = $CanvasLayer/PossibleCards/Support/TypeSelect
@onready var support_limited_select = $CanvasLayer/PossibleCards/Support/LimitedSelect
@onready var support_search = $CanvasLayer/PossibleCards/Support/Search

#Filter dictionaries
var oshi_filter = {"Color":null,"Name":null,"Search":""}
var holomem_filter = {"Color":null,"Name":null,"Level":null,"Buzz":null,"Tag":[],"Search":""}
var support_filter = {"Type":null,"Limited":null,"Search":""}

#The ability to add/remove multiples of cheer at once
@onready var cheer_multiple_label = $CanvasLayer/PossibleCards/Cheer/Multiple
var cheer_multiple = 1

#Various containers/objects we'll need
@onready var oshi_tab = $CanvasLayer/PossibleCards/Oshi/ScrollContainer/ColorRect
@onready var holomem_tab = $CanvasLayer/PossibleCards/Holomem/ScrollContainer/ColorRect
@onready var support_tab = $CanvasLayer/PossibleCards/Support/ScrollContainer/ColorRect
@onready var cheer_tab = $CanvasLayer/PossibleCards/Cheer/ScrollContainer/ColorRect
@onready var main_deck = $CanvasLayer/YourStuff/Deck/MainDeck/ColorRect
@onready var cheer_deck = $CanvasLayer/YourStuff/Deck/CheerDeck/ColorRect
@onready var main_count = $CanvasLayer/YourStuff/Deck/MainCount
@onready var cheer_count = $CanvasLayer/YourStuff/Deck/CheerCount
@onready var analytics = $CanvasLayer/YourStuff/Analytics/ScrollContainer/Stats
@onready var list_of_decks_to_overwrite = $CanvasLayer/SavePrompt/ScrollContainer/VBoxContainer

#A hardcoded order for support types. I should probably make one for tags at some point...
#Color order is handled by Card.get_color_order
@onready var support_order = ["Staff","Item","Event","Tool","Mascot","Fan"]

#Those aforementioned SleeveSelects
@onready var mainSleeveSelect = $CanvasLayer/YourStuff/Sleeves/Main
@onready var cheerSleeveSelect = $CanvasLayer/YourStuff/Sleeves/Cheer
@onready var oshiSleeveSelect = $CanvasLayer/YourStuff/Sleeves/Oshi

#endregion

#The next two calculate mulligan probabilities for analytics purposes
#Assume 50 cards in a deck - number is meaningless otherwise
func choose(n,k):
	var result = 1
	for i in range(k):
		result = (result * (n-i))/(i+1)
	return float(result)

func mulligan_odds(draw_count):
	return choose(50 - total_debut,draw_count)/choose(50,draw_count)

# Stolen from https://forum.godotengine.org/t/how-do-you-get-all-nodes-of-a-certain-class/9143/2
func findByClass(node: Node, className : String, result : Array) -> void:
	if node.is_class(className) :
		result.push_back(node)
	for child in node.get_children():
		findByClass(child, className, result)


func _ready() -> void:
	tr("LEVEL_ANY") #for POT generation - Godot's automatic system won't find it in a popupmenu list
	
	#We find cards iterating through cardHasArt to more easily get alt arts as separate options
	#Card.setup_info will automatically change the art to a proxy if it thinks it should but the
	#	proxy already has an cardHasArt row so we have to make sure we don't double up using
	#	the cardsFound array
	
	var art_data = Database.db.select_rows("cardHasArt","",["cardID","art_index","unrevealed"])
	art_data.sort_custom(custom_art_row_sort) #Really simple sort that every type but cheer overwrites
	
	for art_row in art_data:
		var cardNumber = art_row.cardID
		var artCode = art_row.art_index
		if (bool(art_row.unrevealed) and !Settings.settings.AllowUnrevealed) or [cardNumber, artCode] in cardsFound:
			continue
		cardsFound.append([cardNumber, artCode])
		var newCardButton = create_card_button(cardNumber,artCode)
		
		#We add the constants we've found to the proper arrays and add the Card to the proper tab
		match newCardButton.cardType:
			"Oshi":
				for new_color in newCardButton.oshi_color:
					if new_color not in oshi_colors:
						oshi_colors.append(new_color)
				for new_name in newCardButton.oshi_name:
					if new_name not in oshi_names:
						oshi_names.append(new_name)
				oshi_tab.add_child(newCardButton)
			"Cheer":
				cheer_tab.add_child(newCardButton)
			"Holomem":
				for new_color in newCardButton.holomem_color:
					if new_color not in holomem_colors:
						holomem_colors.append(new_color)
				for new_name in newCardButton.holomem_name:
					if new_name not in holomem_names:
						holomem_names.append(new_name)
				for new_tag in newCardButton.tags:
					if new_tag not in holomem_tags:
						holomem_tags.append(new_tag)
				holomem_tab.add_child(newCardButton)
			"Support":
				if newCardButton.supportType not in support_types:
					support_types.append(newCardButton.supportType)
				support_tab.add_child(newCardButton)
		
		newCardButton.scale = Vector2(0.22,0.22)
		newCardButton.card_clicked.connect(_on_menu_card_clicked)
		newCardButton.card_right_clicked.connect(_on_menu_card_right_clicked)
		
		#The cards are Node2Ds instead of Controls, so they can't go in a GridContainer
		#Instead I have to figure out where they should go manually
		#Very finnicky
		var index = newCardButton.get_index()
		newCardButton.position = Vector2(42 + 75*(index % 5), 60 + 100*(index / 5))
	
	#Sort the cards in the selection menus
	holomem_cards = holomem_tab.get_children().duplicate()
	holomem_cards.sort_custom(custom_holomem_sort)
	oshi_cards = oshi_tab.get_children().duplicate()
	oshi_cards.sort_custom(custom_oshi_sort)
	support_cards = support_tab.get_children().duplicate()
	support_cards.sort_custom(custom_support_sort)
	_update_tabs()
	
	
	#Set up filter PopupMenus
	oshi_name_select.get_popup().add_item(tr("NAME_ANY"))
	for oshi_name in oshi_names:
		oshi_name_select.get_popup().add_item(Settings.trans(oshi_name))
	oshi_name_select.get_popup().index_pressed.connect(_on_oshi_name_select)
	
	oshi_color_select.get_popup().add_item(tr("COLOR_ANY"))
	for oshi_color in oshi_colors:
		oshi_color_select.get_popup().add_item(Settings.trans(oshi_color))
	oshi_color_select.get_popup().index_pressed.connect(_on_oshi_color_select)
	
	holomem_name_select.get_popup().add_item(tr("NAME_ANY"))
	for holomem_name in holomem_names:
		holomem_name_select.get_popup().add_item(Settings.trans(holomem_name))
	holomem_name_select.get_popup().index_pressed.connect(_on_holomem_name_select)
	
	holomem_color_select.get_popup().add_item(tr("COLOR_ANY"))
	for holomem_color in holomem_colors:
		holomem_color_select.get_popup().add_item(Settings.trans(holomem_color))
	holomem_color_select.get_popup().index_pressed.connect(_on_holomem_color_select)
	
	holomem_level_select.get_popup().index_pressed.connect(_on_holomem_level_select)
	
	for tag in holomem_tags:
		holomem_tag_select.get_popup().add_check_item(Settings.trans(tag))
	holomem_tag_select.get_popup().index_pressed.connect(_on_holomem_tag_select)
	holomem_tag_select.get_popup().hide_on_checkable_item_selection = false
	
	support_type_select.get_popup().add_item(tr("SUPPORT_TYPE_ANY"))
	for support_type in support_types:
		support_type_select.get_popup().add_item(Settings.trans(support_type))
	support_type_select.get_popup().index_pressed.connect(_on_support_type_select)
	
	
	#Last minute initializations
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()
	$CanvasLayer/InfoPanel.update_word_wrap()
	update_analytics()
	fix_font_size()

#region Filter And Sort

func _oshi_filter(oshi_to_check) -> bool:
	#Determines if a given oshi should be shown, given your selected filters
	#oshi_to_check : Card
	
	if oshi_filter.Color != null:
		if !oshi_to_check.is_color(oshi_filter.Color):
			return false
	
	if oshi_filter.Name != null and !oshi_to_check.has_name(oshi_filter.Name):
		return false
	
	if oshi_filter.Search != "" and !oshi_to_check.fullText.to_lower().contains(oshi_filter.Search.to_lower()):
		return false
	
	return true

func _holomem_filter(holomem_to_check) -> bool:
	#Determines if a given holomem should be shown, given your selected filters
	#holomem_to_check : Card
	
	if holomem_filter.Color != null:
		if !holomem_to_check.is_color(holomem_filter.Color):
			return false
	
	if holomem_filter.Name != null and !holomem_to_check.has_name(holomem_filter.Name):
		return false
	
	if holomem_filter.Level != null and holomem_to_check.level != holomem_filter.Level:
		return false
	
	if holomem_filter.Buzz != null and holomem_to_check.buzz != holomem_filter.Buzz:
		return false
	
	if !holomem_filter.Tag.all(holomem_to_check.has_tag):
		return false
	
	if holomem_filter.Search != "" and !holomem_to_check.fullText.to_lower().contains(holomem_filter.Search.to_lower()):
		return false
	
	return true

func _support_filter(support_to_check) -> bool:
	#Determines if a given support card should be shown, given your selected filters
	#support_to_check : Card
	
	if support_filter.Type != null and support_to_check.supportType != support_filter.Type:
		return false
	
	if support_filter.Limited != null and support_to_check.limited != support_filter.Limited:
		return false
	
	if support_filter.Search != "" and !support_to_check.fullText.to_lower().contains(support_filter.Search.to_lower()):
		return false
	
	return true

func _update_tabs() -> void:
	#Makes sure the card selection tabs look right
	
	#Filter the tabs - we use temp arrays so we can access the filtered cards later
	var temp_holomem_cards = holomem_cards.filter(_holomem_filter)
	var temp_oshi_cards = oshi_cards.filter(_oshi_filter)
	var temp_support_cards = support_cards.filter(_support_filter)
	
	#Display/hide oshis
	var index = 0
	for oshi_card in oshi_cards:
		if oshi_card not in temp_oshi_cards:
			oshi_card.visible = false
			continue
		oshi_card.position = Vector2(42 + 75*(index % 5), 60 + 100*(index / 5))
		oshi_card.visible = true
		index += 1
	$CanvasLayer/PossibleCards/Oshi/ScrollContainer.scroll_vertical = 0 #Reset scrollbar to top
	
	#Display/hide holomems
	index = 0
	for holomem_card in holomem_cards:
		if holomem_card not in temp_holomem_cards:
			holomem_card.visible = false
			continue
		holomem_card.position = Vector2(42 + 75*(index % 5), 60 + 100*(index / 5))
		holomem_card.visible = true
		index += 1
	$CanvasLayer/PossibleCards/Holomem/ScrollContainer.scroll_vertical = 0 #Reset scrollbar to top
	
	#Display/hide supports
	index = 0
	for support_card in support_cards:
		if support_card not in temp_support_cards:
			support_card.visible = false
			continue
		support_card.position = Vector2(42 + 75*(index % 5), 60 + 100*(index / 5))
		support_card.visible = true
		index += 1
	$CanvasLayer/PossibleCards/Support/ScrollContainer.scroll_vertical = 0 #Reset scrollbar to top
	
	#If I were able to use proper GridContainers, this would be unnecessary.
	#Unfortunately, Cards are Node2Ds instead of Controls.
	#So I have to make sure that the tabs are large enough to see all of the cards
	oshi_tab.custom_minimum_size = Vector2(0, (oshi_tab.get_child_count() / 5)*100 + 120)
	holomem_tab.custom_minimum_size = Vector2(0, (holomem_tab.get_child_count()/5)*100 + 120)
	support_tab.custom_minimum_size = Vector2(0, (support_tab.get_child_count()/5)*100 + 120)
	cheer_tab.custom_minimum_size = Vector2(0, (cheer_tab.get_child_count()/5)*100 + 120)

func _on_oshi_name_select(selected_index) -> void:
	var selected_name = oshi_names[selected_index-1]
	
	if selected_index == 0:
		oshi_name_select.text = tr("NAME")
		oshi_filter.Name = null
	else:
		oshi_name_select.text = Settings.trans(selected_name)
		oshi_filter.Name = selected_name
	_update_tabs()

func _on_oshi_color_select(selected_index) -> void:
	var selected_color = oshi_colors[selected_index-1]
	
	if selected_index == 0:
		oshi_color_select.text = tr("COLOR")
		oshi_filter.Color = null
	else:
		oshi_color_select.text = Settings.trans(selected_color)
		oshi_filter.Color = selected_color
	_update_tabs()

func _on_oshi_search(search_text) -> void:
	oshi_filter.Search = search_text
	_update_tabs()

func _on_oshi_clear_filters_pressed() -> void:
	oshi_filter = {"Color":null,"Name":null,"Search":""}
	oshi_color_select.text = tr("COLOR")
	oshi_name_select.text = tr("NAME")
	oshi_search.text = ""
	_update_tabs()


func _on_holomem_name_select(selected_index) -> void:
	var selected_name = holomem_names[selected_index-1]
	
	if selected_index == 0:
		holomem_name_select.text = tr("NAME")
		holomem_filter.Name = null
	else:
		holomem_name_select.text = Settings.trans(selected_name)
		holomem_filter.Name = selected_name
	_update_tabs()

func _on_holomem_color_select(selected_index) -> void:
	var selected_color = holomem_colors[selected_index-1]
	
	if selected_index == 0:
		holomem_color_select.text = tr("COLOR")
		holomem_filter.Color = null
	else:
		holomem_color_select.text = Settings.trans(selected_color)
		holomem_filter.Color = selected_color
	_update_tabs()

func _on_holomem_level_select(selected_index) -> void:
	var selected_level = holomem_level_select.get_popup().get_item_text(selected_index)
	
	holomem_level_select.text = selected_level
	match selected_index:
		1:
			holomem_filter.Level = 0
		2:
			holomem_filter.Level = 1
		3:
			holomem_filter.Level = 2
		4:
			holomem_filter.Level = -1
		_:
			holomem_filter.Level = null
			holomem_level_select.text = tr("LEVEL")
	_update_tabs()

func _on_holomem_buzz_select(is_buzz) -> void:
	if is_buzz:
		holomem_filter.Buzz = true
	else:
		holomem_filter.Buzz = null
	_update_tabs()

func _on_holomem_tag_select(selected_index) -> void:
	var selected_tag = holomem_tags[selected_index]
	var is_checked = !holomem_tag_select.get_popup().is_item_checked(selected_index)
	holomem_tag_select.get_popup().set_item_checked(selected_index,is_checked)
	if is_checked:
		holomem_filter.Tag.append(selected_tag)
	else:
		holomem_filter.Tag.erase(selected_tag)
	_update_tabs()

func _on_holomem_search(search_text) -> void:
	holomem_filter.Search = search_text
	_update_tabs()

func _on_holomem_clear_filters_pressed() -> void:
	holomem_filter = {"Color":null,"Name":null,"Level":null,"Buzz":null,"Tag":[],"Search":""}
	holomem_buzz_select.button_pressed = false
	holomem_color_select.text = tr("COLOR")
	holomem_name_select.text = tr("NAME")
	holomem_level_select.text = tr("LEVEL")
	for index in range(holomem_tag_select.get_popup().item_count):
		holomem_tag_select.get_popup().set_item_checked(index,false)
	holomem_search.text = ""
	_update_tabs()


func _on_support_type_select(selected_index) -> void:
	var selected_type = support_types[selected_index-1]
	
	if selected_index == 0:
		support_type_select.text = tr("SUPPORT_TYPE")
		support_filter.Type = null
	else:
		support_type_select.text = Settings.trans(selected_type)
		support_filter.Type = selected_type
	_update_tabs()

func _on_support_limited_select(is_limited) -> void:
	if is_limited:
		support_filter.Limited = true
	else:
		support_filter.Limited = null
	_update_tabs()

func _on_support_search(search_text):
	support_filter.Search = search_text
	_update_tabs()

func _on_support_clear_filters_pressed() -> void:
	support_filter = {"Type":null,"Limited":null,"Search":""}
	support_limited_select.button_pressed = false
	support_type_select.text = tr("SUPPORT_TYPE")
	support_search.text = ""
	_update_tabs()

func custom_art_row_sort(a,b) -> bool:
	#The generic sort that just goes card number -> art index
	
	if a.cardID < b.cardID:
		return true
	elif a.cardID == b.cardID and a.art_index < b.art_index:
		return true
	else:
		return false

func custom_holomem_sort(a,b) -> bool:
	#The holomem sort goes Color -> Name -> Level -> card number -> art index
	#We need to double up on a lot of conditions to make sure they're sorted consistently
	
	if b.holomem_color.size() == 0 and a.holomem_color.size() > 0:
		return true
	elif a.holomem_color.size() == 0 and b.holomem_color.size() > 0:
		return false
	elif a.getColorOrder() < b.getColorOrder():
		return true
	elif a.getColorOrder() > b.getColorOrder():
		return false
	elif a.getNamesAsText() < b.getNamesAsText():
		return true
	elif a.getNamesAsText() > b.getNamesAsText():
		return false
	elif a.level < b.level:
		return true
	elif a.level > b.level:
		return false
	elif a.cardNumber < b.cardNumber:
		return true
	elif a.cardNumber > b.cardNumber:
		return false
	elif a.artNum < b.artNum:
		return true
	else:
		return false

func custom_oshi_sort(a,b) -> bool:
	#The oshi sort goes color -> name -> card number -> art index
	#We need to double up on a lot of conditions to make sure they're sorted consistently
	
	if b.oshi_color.size() == 0 and a.oshi_color.size() > 0:
		return true
	elif a.oshi_color.size() == 0 and b.oshi_color.size() > 0:
		return false
	elif a.getColorOrder() < b.getColorOrder():
		return true
	elif a.getColorOrder() > b.getColorOrder():
		return false
	elif a.getNamesAsText() < b.getNamesAsText():
		return true
	elif a.getNamesAsText() > b.getNamesAsText():
		return false
	elif a.cardNumber < b.cardNumber:
		return true
	elif a.cardNumber > b.cardNumber:
		return false
	elif a.artNum < b.artNum:
		return true
	else:
		return false

func custom_support_sort(a,b) -> bool:
	#The support sort goes type -> card number -> art index
	#We need to double up on a lot of conditions to make sure they're sorted consistently
	
	if support_order.find(a.supportType) < support_order.find(b.supportType):
		return true
	elif support_order.find(a.supportType) > support_order.find(b.supportType):
		return false
	elif a.cardNumber < b.cardNumber:
		return true
	elif a.cardNumber > b.cardNumber:
		return false
	elif a.artNum < b.artNum:
		return true
	else:
		return false

func custom_main_sort(a,b) -> bool:
	#The main deck is sorted Holomem -> Support
	#Okay, technically Cheer -> Holomem -> Oshi -> Support but that's not legal
	
	if a.cardType < b.cardType:
		return true
	elif a.cardType > b.cardType:
		return false
	elif a.cardType == "Holomem":
		return custom_holomem_sort(a,b)
	elif a.cardType == "Support":
		return custom_support_sort(a,b)
	else:
		return false
#endregion

#region Deck Modification
func load_from_deck_info(deck_info : Dictionary) -> void:
	#Takes a deck in dictionary form and creates it in the builder
	#deck_info : Dictionary - the deck read from typically a json file
	
	#Clears everything except the oshi card (if it exists)
	#The timing of deletion is weird and it may not be done by the time the rest of the code runs
	_on_clear_pressed(false)
	
	#Make an oshi card if none exist or modify the one that does
	if oshiCard == null:
		create_oshi(deck_info.oshi[0],deck_info.oshi[1])
	else:
		oshiCard.setup_info(deck_info.oshi[0],deck_info.oshi[1])
	
	#Create cards in deck
	for card_info in deck_info.deck:
		create_main_deck_card(card_info[0],card_info[2],card_info[1])
	for card_info in deck_info.cheerDeck:
		create_cheer_deck_card(card_info[0],card_info[2],card_info[1])
	
	#Set up sleeves
	if deck_info.has("sleeve"):
		var image = Image.new()
		image.load_webp_from_buffer(deck_info.sleeve)
		mainSleeveSelect.new_sleeve(image)
	else:
		mainSleeveSelect.new_sleeve()
	if deck_info.has("cheerSleeve"):
		var image = Image.new()
		image.load_webp_from_buffer(deck_info.cheerSleeve)
		cheerSleeveSelect.new_sleeve(image)
	else:
		cheerSleeveSelect.new_sleeve()
	if deck_info.has("oshiSleeve"):
		var image = Image.new()
		image.load_webp_from_buffer(deck_info.oshiSleeve)
		oshiSleeveSelect.new_sleeve(image)
	else:
		oshiSleeveSelect.new_sleeve()
	
	
	#Visual stuff
	update_main_deck_children()
	update_cheer_deck_children()
	
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"
	$CanvasLayer/DeckName.text = deck_info.deckName
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()
	
	_hide_deck_list()

func add_holomem_or_support(card_added, amount=1) -> void:
	#Run whenever a holomem (or support) card is added (or removed) from the deck
	#Just keeps tracks of analytics stats
	#card_added : Card - said holomem or support card
	#amount : how many are being added at once (can be negative)
	
	if card_added.cardType == "Holomem":
		match card_added.level:
			0:
				total_debut += amount
			1:
				total_1st += amount
			2:
				total_2nd += amount
			-1:
				total_spot += amount
		
		for added_color in card_added.holomem_color:
			if total_color.has(added_color):
				total_color[added_color] += amount
			else:
				total_color[added_color] = max(0, amount)
	elif card_added.cardType == "Support":
		total_support += amount
	
	update_analytics()

func create_card_button(number : String, art_code : int):
	#Returns a Card object that will act as a button
	#The actual button functionality is added by whatever code calls this
	#For both card selection and your deck
	
	var new_id = all_cards.size()
	var newCard = card.instantiate()
	newCard.name = "Card" + str(new_id)
	newCard.setup_info(number,art_code)
	newCard.cardID = new_id
	
	newCard.card_mouse_over.connect(update_info)
	all_cards.append(newCard)
	
	return newCard

func create_oshi(number : String, art_code : int) -> void:
	#Creates the oshi card for your deck
	
	oshiCard = create_card_button(number,art_code)
	oshiCard.position = Vector2(65,500)
	oshiCard.scale = Vector2(0.38,0.38)
	$CanvasLayer/YourStuff/Deck.add_child(oshiCard)

func create_main_deck_card(number : String, art_code : int, amount = 1) -> void:
	
	var newCardButton = create_card_button(number,art_code)
	newCardButton.scale = Vector2(0.28,0.28)
	newCardButton.update_amount(amount)
	total_main += amount
	newCardButton.set_amount_hidden(true)
	main_deck.add_child(newCardButton)
	newCardButton.card_clicked.connect(_on_deck_card_clicked)
	newCardButton.card_right_clicked.connect(_on_deck_card_right_clicked)
	add_holomem_or_support(newCardButton,amount)
	if in_deck_dictionary.has(number):
		in_deck_dictionary[number] += amount
	else:
		in_deck_dictionary[number] = amount

func create_cheer_deck_card(number,art_code,amount = 1):
	var newCardButton = create_card_button(number,art_code)
	newCardButton.scale = Vector2(0.31,0.31)
	newCardButton.update_amount(amount)
	total_cheer += amount
	newCardButton.set_amount_hidden(true)
	cheer_deck.add_child(newCardButton)
	newCardButton.card_clicked.connect(_on_deck_card_clicked)
	newCardButton.card_right_clicked.connect(_on_deck_card_right_clicked)
	if in_deck_dictionary.has(number):
		in_deck_dictionary[number] += amount
	else:
		in_deck_dictionary[number] = amount
#endregion

#region Buttons To Modify Deck
func find_in_deck_with_number(cardNumber,artNum,areaToCheck):
	for cardButton in areaToCheck.get_children():
		if cardButton.cardNumber == cardNumber and artNum == cardButton.artNum:
			return cardButton

func _on_menu_card_clicked(card_id):
	if $CanvasLayer/DeckList.visible or $CanvasLayer/SavePrompt.visible:
		return
	
	var actualCard = all_cards[card_id]
	match actualCard.cardType:
		"Oshi":
			if oshiCard == null:
				create_oshi(actualCard.cardNumber,actualCard.artNum)
			else:
				oshiCard.setup_info(actualCard.cardNumber,actualCard.artNum)
		"Cheer":
			var alreadyHere = find_in_deck_with_number(actualCard.cardNumber,actualCard.artNum,cheer_deck)
			if alreadyHere == null:
				create_cheer_deck_card(actualCard.cardNumber,actualCard.artNum,cheer_multiple)
				update_cheer_deck_children()
			else:
				alreadyHere.set_amount_hidden(true)
				alreadyHere.update_amount(alreadyHere.get_amount()+cheer_multiple)
				in_deck_dictionary[actualCard.cardNumber] += cheer_multiple
				total_cheer += cheer_multiple
		_:
			var alreadyHere = find_in_deck_with_number(actualCard.cardNumber,actualCard.artNum,main_deck)
			if alreadyHere == null:
				create_main_deck_card(actualCard.cardNumber,actualCard.artNum)
				update_main_deck_children()
			else:
				alreadyHere.set_amount_hidden(true)
				alreadyHere.update_amount(alreadyHere.get_amount()+1)
				in_deck_dictionary[actualCard.cardNumber] += 1
				#deck_info.deck
				total_main += 1
				add_holomem_or_support(alreadyHere)
	
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()

func _on_menu_card_right_clicked(card_id):
	if $CanvasLayer/DeckList.visible or $CanvasLayer/SavePrompt.visible:
		return
	
	var actualCard = all_cards[card_id]
	if actualCard.cardType == "Oshi":
		return
	var alreadyHere
	if actualCard.cardType == "Cheer":
		alreadyHere = find_in_deck_with_number(actualCard.cardNumber,actualCard.artNum,cheer_deck)
		if alreadyHere != null:
			alreadyHere.set_amount_hidden(true)
			var amount_to_remove = min(cheer_multiple,in_deck_dictionary[actualCard.cardNumber])
			alreadyHere.update_amount(alreadyHere.get_amount()-amount_to_remove)
			in_deck_dictionary[actualCard.cardNumber] -= amount_to_remove
			#deck_info.cheerDeck
			total_cheer -= amount_to_remove
	else:
		alreadyHere = find_in_deck_with_number(actualCard.cardNumber,actualCard.artNum,main_deck)
		if alreadyHere != null:
			alreadyHere.set_amount_hidden(true)
			alreadyHere.update_amount(alreadyHere.get_amount()-1)
			in_deck_dictionary[actualCard.cardNumber] -= 1
			#deck_info.cheerDeck
			total_main -= 1
			add_holomem_or_support(alreadyHere,-1)
	
	if alreadyHere != null and in_deck_dictionary[actualCard.cardNumber] <= 0:
		in_deck_dictionary.erase(actualCard.cardNumber)
		alreadyHere.name = "PleaseDelete"
		alreadyHere.queue_free()
		update_main_deck_children()
		update_cheer_deck_children()
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"

func _on_deck_card_clicked(card_id):
	if $CanvasLayer/DeckList.visible or $CanvasLayer/SavePrompt.visible:
		return
	
	var actualCard = all_cards[card_id]
	actualCard.update_amount(actualCard.get_amount()-1)
	in_deck_dictionary[actualCard.cardNumber] -= 1
	if actualCard.cardType == "Cheer":
		total_cheer -= 1
	else:
		add_holomem_or_support(actualCard,-1)
		total_main -= 1
	if actualCard.get_amount() <= 0:
		actualCard.name = "PleaseDelete"
		actualCard.queue_free()
		update_main_deck_children()
		update_cheer_deck_children()
	if in_deck_dictionary[actualCard.cardNumber] <= 0:
		in_deck_dictionary.erase(actualCard.cardNumber)
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()

func _on_deck_card_right_clicked(card_id):
	if $CanvasLayer/DeckList.visible or $CanvasLayer/SavePrompt.visible:
		return
	
	var actualCard = all_cards[card_id]
	actualCard.update_amount(actualCard.get_amount()+1)
	in_deck_dictionary[actualCard.cardNumber] += 1
	if actualCard.cardType == "Cheer":
		total_cheer += 1
	else:
		total_main += 1
		add_holomem_or_support(actualCard)
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()

func _on_cheer_multiple_set(new_multiple):
	cheer_multiple = new_multiple
	cheer_multiple_label.text = str(new_multiple) + "x"
#endregion

#region Update Visuals/Cleanup
func is_deck_legal():
	$CanvasLayer/Problems/ProblemList.text = ""
	
	var nonsensical = false
	
	if oshiCard == null or oshiCard.name.contains("PleaseDelete"):
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_NOOSHI") + "\n"
	elif oshiCard.cardType != "Oshi":
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_FAKEOSHI").format({cardNum = oshiCard.cardNumber}) + "\n"
		nonsensical = true
	
	if total_main < 50:
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_UNDERDECK") + "\n"
	elif total_main > 50:
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_OVERDECK") + "\n"
	if total_cheer < 20:
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_UNDERCHEER") + "\n"
	elif total_cheer > 20:
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_OVERCHEER") + "\n"
	
	var found_debut = false
	var too_many_copies = false
	
	for cardButton in main_deck.get_children():
		if cardButton.cardType == "Holomem" and cardButton.level == 0 and !cardButton.name.contains("PleaseDelete"):
			found_debut = true
		if cardButton.get_amount() < 0:
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_NEGATIVEAMOUNT").format({cardNum = cardButton.cardNumber}) + "\n"
			nonsensical = true
		if cardButton.cardType in ["Cheer","Oshi"]:
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_FAKEMAIN").format({cardNum = cardButton.cardNumber}) + "\n"
			nonsensical = true
	if !found_debut:
		$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_NODEBUTS") + "\n"
	
	for cardButton in cheer_deck.get_children():
		if cardButton.get_amount() < 0:
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_NEGATIVEAMOUNT").format({cardNum = cardButton.cardNumber}) + "\n"
			nonsensical = true
		if cardButton.cardType in ["Holomem","Support"]:
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_FAKECHEER").format({cardNum = cardButton.cardNumber}) + "\n"
			nonsensical = true
	
	for cardNumber in in_deck_dictionary:
		var data = Database.db.select_rows("mainCards","cardID LIKE '" + cardNumber + "'", ["*"])[0]
		if data.cardLimit != -1 and in_deck_dictionary[cardNumber] > data.cardLimit:
			too_many_copies = true
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_OVERAMOUNT").format({cardNum = cardNumber}) + "\n"
		if in_deck_dictionary[cardNumber] < 0:
			$CanvasLayer/Problems/ProblemList.text += tr("DECKERROR_NEGATIVEAMOUNT").format({cardNum = cardNumber}) + "\n"
			nonsensical = true
	
	return total_main == 50 and total_cheer == 20 and oshiCard != null and found_debut and !too_many_copies and !nonsensical

func update_main_deck_children():
	var main_cards = main_deck.get_children().duplicate()
	main_cards.sort_custom(custom_main_sort)
	var index = 0
	for cardButton in main_cards:
		if cardButton.name.contains("PleaseDelete"):
			continue
		cardButton.position = Vector2(48 + 92*(index % 6), 70 + 130*(index / 6))
		index += 1
	main_deck.custom_minimum_size = Vector2(0, (index / 6)*130 + 140)

func update_cheer_deck_children():
	var index = 0
	for cardButton in cheer_deck.get_children():
		if cardButton.name.contains("PleaseDelete"):
			continue
		cardButton.position = Vector2(60 + 120*index, 80)
		index += 1
	cheer_deck.custom_minimum_size = Vector2(index*120 + 70, 0)

func update_analytics():
	var result = ""
	
	result += "/".join([tr("LEVEL_DEBUT"),tr("LEVEL_1"),tr("LEVEL_2"),tr("LEVEL_SPOT")]) + "\n%0*d/%0*d/%0*d/%0*d\n\n" % [2,total_debut,2,total_1st,2,total_2nd,2,total_spot]
	
	result += "/".join(["White","Green","Red","Blue","Purple","Yellow"]) + "\n%0*d/%0*d/%0*d/%0*d/%0*d/%0*d\n\n" \
	% [2,total_color.get("White",0),2,total_color.get("Green",0),
	2,total_color.get("Red",0),2,total_color.get("Blue",0),
	2,total_color.get("Purple",0),2,total_color.get("Yellow",0)]
	
	result += "Holomems/Support\n%0*d/%0*d\n\n" % [2, total_debut+total_1st+total_2nd+total_spot, 2, total_support]
	
	var mulligan = mulligan_odds(7)
	result += "Chance of forced mulligan Free/6/5/4/3/2/1/Loss\n%.2f%%" % (mulligan * 100)
	for i in range(7,0,-1):
		mulligan *= mulligan_odds(i)
		result += "/%.2f%%" % (mulligan * 100)
	
	analytics.text = result

func update_info(card_id):
	$CanvasLayer/InfoPanel._new_info(all_cards[card_id],all_cards[card_id])

func clear_info():
	$CanvasLayer/InfoPanel._clear_showing()
#endregion

#region Bottom Bar Buttons
func _on_load_deck_pressed():
	$CanvasLayer/DeckList._all_decks()
	$CanvasLayer/DeckList.visible = true

func _hide_deck_list():
	$CanvasLayer/DeckList.visible = false

func _on_save_deck_pressed():
	for deckButton in list_of_decks_to_overwrite.get_children():
		deckButton.queue_free()
	var path = "user://Decks"
	var dir = DirAccess.open(path)
	if dir:
		for file_name in dir.get_files():
			if file_name.ends_with(".json"):
				var deckButton = Button.new()
				deckButton.text = tr("DECK_OVERWRITE").format({fileName = file_name})
				deckButton.pressed.connect(_save_deck_to_file.bind(path + "/" + file_name))
				list_of_decks_to_overwrite.add_child(deckButton)
	else:
		print("An error occurred when trying to access the path.")
	$CanvasLayer/SavePrompt.visible = true

func _save_deck_to_file(path):
	if !path.ends_with(".json"):
		path += ".json"
	
	var deck_info = {}
	
	if $CanvasLayer/DeckName.text == "":
		deck_info.deckName = $CanvasLayer/DeckName.placeholder_text
	else:
		deck_info.deckName = $CanvasLayer/DeckName.text
	
	deck_info.oshi = [oshiCard.cardNumber,oshiCard.artNum]
	
	deck_info.deck = []
	deck_info.cheerDeck = []
	
	if mainSleeveSelect.current_sleeve != null:
		deck_info.sleeve = Array(mainSleeveSelect.current_sleeve.save_webp_to_buffer(true, 0.45))
	if cheerSleeveSelect.current_sleeve != null:
		deck_info.cheerSleeve = Array(cheerSleeveSelect.current_sleeve.save_webp_to_buffer(true, 0.45))
	if oshiSleeveSelect.current_sleeve != null:
		deck_info.oshiSleeve = Array(oshiSleeveSelect.current_sleeve.save_webp_to_buffer(true, 0.45))
	
	for cB in main_deck.get_children():
		deck_info.deck.append([cB.cardNumber,cB.get_amount(),cB.artNum])
	
	for cB in cheer_deck.get_children():
		deck_info.cheerDeck.append([cB.cardNumber,cB.get_amount(),cB.artNum])
	
	var json_string := JSON.stringify(deck_info)
	# We will need to open/create a new file for this data string
	var file_access := FileAccess.open(path, FileAccess.WRITE)
	if not file_access:
		print("An error happened while saving data: ", FileAccess.get_open_error())
		return

	file_access.store_line(json_string)
	file_access.close()
	
	_hide_save_prompt()

func _on_save_pressed(confirmed=false):
	var file_name = $CanvasLayer/SavePrompt/FileName.text
	if file_name == "":
		file_name = $CanvasLayer/SavePrompt/FileName.placeholder_text
	if !file_name.ends_with(".json"):
		file_name += ".json"
	if !confirmed and FileAccess.file_exists("user://Decks/" + file_name):
		$CanvasLayer/SavePrompt/OverwriteConfirm/Label.text = "Overwrite " + file_name + "?"
		$CanvasLayer/SavePrompt/OverwriteConfirm.visible = true
		$CanvasLayer/SavePrompt/ScrollContainer.scroll_vertical = 0
	else:
		_save_deck_to_file("user://Decks/" + file_name)

func _hide_save_prompt():
	$CanvasLayer/SavePrompt.visible = false
	$CanvasLayer/SavePrompt/OverwriteConfirm.visible = false
	$CanvasLayer/SavePrompt/OverwriteConfirm/Label.text = ""

func _on_main_menu_pressed():
	get_tree().change_scene_to_file("res://Scenes/board.tscn")

func _on_clear_pressed(complete=true):
	in_deck_dictionary = {}
	total_cheer = 0
	total_main = 0
	total_debut = 0
	total_1st = 0
	total_2nd = 0
	total_spot = 0
	total_color = {}
	total_support = 0
	for cB in main_deck.get_children():
		cB.name = "PleaseDelete"
		cB.queue_free()
	for cB in cheer_deck.get_children():
		cB.name = "PleaseDelete"
		cB.queue_free()
	if oshiCard != null and complete:
		oshiCard.name = "PleaseDelete"
		oshiCard.queue_free()
	
	update_main_deck_children()
	update_cheer_deck_children()
	main_count.text = str(total_main) + "/50"
	cheer_count.text = str(total_cheer) + "/20"
	update_analytics()
	
	$CanvasLayer/SaveDeck.disabled = !is_deck_legal()
#endregion

func fix_font_size() -> void:
	#Different languages have different text sizes. I've been managing the labels manually (bad)
	#	but buttons had too much variance for one font size to work.
	#Check fix_font_tool.gd
	
	var all_labels = []
	findByClass(self, "Button", all_labels)
	for label in all_labels:
		if label.auto_translate:
			if !label.has_meta("fontSize"):
				label.set_meta("fontSize", label.get_theme_font_size("font_size"))
			#Scale is 0.9 here but 0.8 on the main menu. This is intentional, and returns the best results
			FixFontTool.apply_text_with_corrected_max_scale(label.size, label, tr(label.text), 0.9, false, Vector2(), label.get_meta("fontSize"))
