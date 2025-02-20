/obj/structure/holopay
	name = "holographic pay stand"
	desc = "an unregistered pay stand"
	icon = 'icons/obj/economy.dmi'
	icon_state = "card_scanner"
	alpha = 150
	anchored = TRUE
	armor = list(MELEE = 0, BULLET = 50, LASER = 50, ENERGY = 50, BOMB = 0, BIO = 0, FIRE = 20, ACID = 20)
	max_integrity = 15
	layer = FLY_LAYER
	/// ID linked to the holopay
	var/datum/weakref/card_ref
	/// Max range at which the hologram can be projected before it deletes
	var/max_holo_range = 4
	/// The holopay shop icon displayed in the UI
	var/shop_logo = "donate"
	/// Replaces the "pay whatever" functionality with a set amount when non-zero.
	var/force_fee = 0
	/// Current holder of the linked card
	var/datum/weakref/holder

/obj/structure/holopay/examine(mob/user)
	. = ..()
	if(force_fee)
		. += span_boldnotice("This holopay forces a payment of <b>[force_fee]</b> credit\s per swipe instead of a variable amount.")

/obj/structure/holopay/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	if(!user.combat_mode)
		ui_interact(user)
		return .
	user.do_attack_animation(src, ATTACK_EFFECT_PUNCH)
	user.changeNext_move(CLICK_CD_MELEE)
	take_damage(5, BRUTE, MELEE, 1)

/obj/structure/holopay/play_attack_sound(damage_amount, damage_type = BRUTE, damage_flag = 0)
	switch(damage_type)
		if(BRUTE)
			playsound(loc, 'sound/weapons/egloves.ogg', 80, TRUE)
		if(BURN)
			playsound(loc, 'sound/weapons/egloves.ogg', 80, TRUE)

/obj/structure/holopay/deconstruct()
	dissapate()
	return ..()

/obj/structure/holopay/attackby(obj/item/held_item, mob/holder, params)
	var/mob/living/user = holder
	if(!isliving(user))
		return ..()
	/// Users can pay with an ID to skip the UI
	if(istype(held_item, /obj/item/card/id))
		if(force_fee && tgui_alert(holder, "This holopay has a [force_fee] cr fee. Confirm?", "Holopay Fee", list("Pay", "Cancel")) != "Pay")
			return TRUE
		process_payment(user)
		return TRUE
	/// Users can also pay by holochip
	if(istype(held_item, /obj/item/holochip))
		/// Account checks
		var/obj/item/holochip/chip = held_item
		if(!chip.credits)
			balloon_alert(user, "holochip is empty")
			to_chat(user, span_warning("There doesn't seem to be any credits here."))
			return FALSE
		/// Charges force fee or uses pay what you want
		var/cash_deposit = force_fee || tgui_input_number(user, "How much? (Max: [chip.credits])", "Patronage", max_value = chip.credits)
		/// Exit sanity checks
		if(!cash_deposit)
			return TRUE
		if(QDELETED(held_item) || QDELETED(user) || QDELETED(src) || !user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
			return FALSE
		if(!chip.spend(cash_deposit, FALSE))
			balloon_alert(user, "insufficient credits")
			to_chat(user, span_warning("You don't have enough credits to pay with this chip."))
			return FALSE
		/// Success: Alert buyer
		alert_buyer(user, cash_deposit)
		return TRUE
	/// Throws errors if they try to use space cash
	if(istype(held_item, /obj/item/stack/spacecash))
		to_chat(user, "What is this, the 2000s? We only take card here.")
		return TRUE
	if(istype(held_item, /obj/item/coin))
		to_chat(user, "What is this, the 1800s? We only take card here.")
		return TRUE
	return ..()

/obj/structure/holopay/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	if(.)
		return FALSE
	var/mob/living/interactor = user
	if(isliving(interactor) && interactor.combat_mode)
		return FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "HoloPay")
		ui.open()

/obj/structure/holopay/ui_status(mob/user)
	. = ..()
	if(!in_range(user, src) && !isobserver(user))
		return UI_CLOSE

/obj/structure/holopay/ui_static_data(mob/user)
	. = list()
	/// Sanity checks
	var/obj/item/card/id/linked_card = get_card()
	.["available_logos"] = linked_card.available_logos
	.["description"] = desc
	.["max_fee"] = linked_card.holopay_max_fee
	.["owner"] = linked_card.registered_account?.account_holder || null
	.["shop_logo"] = shop_logo

/obj/structure/holopay/ui_data(mob/user)
	. = list()
	.["force_fee"] = force_fee
	.["name"] = name
	if(!isliving(user))
		return .
	var/mob/living/card_holder = user
	var/obj/item/card/id/id_card = card_holder.get_idcard(TRUE)
	var/datum/bank_account/account = id_card?.registered_account || null
	if(account)
		.["user"] = list()
		.["user"]["name"] = account.account_holder
		.["user"]["balance"] = account.account_balance

/obj/structure/holopay/ui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return FALSE
	var/obj/item/card/id/linked_card = get_card()
	switch(action)
		if("done")
			ui.send_full_update()
			return TRUE
		if("fee")
			linked_card.set_holopay_fee(params["amount"])
			force_fee = linked_card.holopay_fee
		if("logo")
			linked_card.set_holopay_logo(params["logo"])
			shop_logo = linked_card.holopay_logo
		if("pay")
			ui.close()
			process_payment(usr)
			return TRUE
		if("rename")
			linked_card.set_holopay_name(params["name"])
			name = linked_card.holopay_name
	return FALSE

/**
 * Links the source card to the holopay. Begins checking if its in range.
 *
 * Parameters:
 * * turf/target - The tile to project the holopay onto
 * * obj/item/card/id/card - The card to link to the holopay
 * Returns:
 * * TRUE - the card was linked
 */
/obj/structure/holopay/proc/assign_card(turf/target, obj/item/card/id/card)
	card_ref = WEAKREF(card)
	desc = "Pays directly into [card.registered_account.account_holder]'s bank account."
	force_fee = card.holopay_fee
	shop_logo = card.holopay_logo
	name = card.holopay_name
	add_atom_colour("#77abff", FIXED_COLOUR_PRIORITY)
	set_light(2)
	visible_message(span_notice("A holographic pay stand appears."))
	/// Start checking if the source projection is in range
	RegisterSignal(card, COMSIG_MOVABLE_MOVED, .proc/check_operation)
	if(card.loc)
		holder = WEAKREF(card.loc)
		RegisterSignal(card.loc, COMSIG_MOVABLE_MOVED, .proc/check_operation)
	return TRUE

/**
 * A periodic check to see if the projecting card is nearby.
 * Deletes the holopay if true.
 */
/obj/structure/holopay/proc/check_operation()
	SIGNAL_HANDLER
	var/obj/item/card/id/linked_card = get_card()
	var/card_holder = holder?.resolve()
	if(!card_holder || linked_card.loc != card_holder)
		if(card_holder)
			UnregisterSignal(card_holder, COMSIG_MOVABLE_MOVED)
		holder = WEAKREF(linked_card.loc)
		RegisterSignal(linked_card.loc, COMSIG_MOVABLE_MOVED, .proc/check_operation)
	if(!IN_GIVEN_RANGE(src, linked_card, max_holo_range) || !IN_GIVEN_RANGE(src, linked_card.loc, max_holo_range))
		dissapate()

/**
 * Creates holopay vanishing effects.
 * Deletes the holopay thereafter.
 */
/obj/structure/holopay/proc/dissapate()
	var/obj/item/card/id/linked_card = get_card()
	playsound(loc, "sound/effects/empulse.ogg", 40, TRUE)
	visible_message(span_notice("The pay stand vanishes."))
	QDEL_NULL(linked_card.holopay_ref)

/**
 * Checks that the card is still linked.
 * Deletes the holopay if not.
 *
 * Returns:
 * * /obj/item/card/id/card - The card that is linked to the holopay
 */
/obj/structure/holopay/proc/get_card()
	var/obj/item/card/id/linked_card = card_ref?.resolve()
	if(!linked_card || !istype(linked_card, /obj/item/card/id))
		stack_trace("Could not link a holopay to a valid card.")
		qdel(src)
	return linked_card

/**
 * Initiates a transaction between accounts.
 *
 * Parameters:
 * * mob/living/user - The user who initiated the transaction.
 * Returns:
 * * TRUE - transaction was successful
 */
/obj/structure/holopay/proc/process_payment(mob/living/user)
	// Preliminary sanity checks
	var/obj/item/card/id/linked_card = get_card()
	/// Account checks
	var/obj/item/card/id/id_card
	id_card = user.get_idcard(TRUE)
	if(!id_card || !id_card.registered_account || !id_card.registered_account.account_job)
		balloon_alert(user, "invalid account")
		to_chat(user, span_warning("You don't have a valid account."))
		return FALSE
	var/datum/bank_account/payee = id_card.registered_account
	if(payee == linked_card.registered_account)
		balloon_alert(user, "invalid transaction")
		to_chat(user, span_warning("You can't pay yourself."))
		return FALSE
	/// If the user has enough money, ask them the amount or charge the force fee
	var/amount = force_fee || tgui_input_number(user, "How much? (Max: [payee.account_balance])", "Patronage", max_value = payee.account_balance)
	/// Exit checks in case the user cancelled or entered an invalid amount
	if(!amount || QDELETED(user) || QDELETED(src) || !user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		return FALSE
	if(!payee.adjust_money(-amount))
		balloon_alert(user, "insufficient credits")
		to_chat(user, span_warning("You don't have the money to pay for this."))
		return FALSE
	/// Success: Alert the buyer
	alert_buyer(user, amount)
	return TRUE

/**
 * Alerts the owner of the transaction.
 *
 * Parameters:
 * * payee - The user who initiated the transaction.
 * * amount - The amount of money that was paid.
 * Returns:
 * * TRUE - alert was successful.
 */
/obj/structure/holopay/proc/alert_buyer(payee, amount)
	/// Sanity checks
	var/obj/item/card/id/linked_card = get_card()
	/// Pay the owner
	linked_card.registered_account.adjust_money(amount)
	/// Make alerts
	linked_card.registered_account.bank_card_talk("[payee] has deposited [amount] cr at your holographic pay stand.")
	say("Thank you for your patronage, [payee]!")
	playsound(src, 'sound/effects/cashregister.ogg', 20, TRUE)
	/// Log the event
	log_econ("[amount] credits were transferred from [payee]'s transaction to [linked_card.registered_account.account_holder]")
	SSblackbox.record_feedback("amount", "credits_transferred", amount)
	return TRUE
