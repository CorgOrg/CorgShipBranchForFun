/datum/shuttle_data
	/// Port ID of the shuttle
	var/port_id
	/// List of attached shield generators
	var/list/obj/machinery/power/shuttle_shield_generator/registered_shield_generators = list()
	/// List of engine heaters
	var/list/obj/machinery/shuttle/engine/registered_engines = list()
	/// Stored shield power
	var/shield_health = 0
	/// Calculate fuel consumption rate
	var/fuel_consumption
	/// The thrust of the shuttle
	/// Updates when engines run out of fuel, are dismantled or created
	var/thrust
	/// The mass of the shuttle
	/// Updated when the shuttle size is changed
	var/mass
	/// Detection radius (Debug)
	var/detection_range = 1000
	/// Interidction range
	var/interdiction_range = 150

/datum/shuttle_data/New(port_id)
	. = ..()
	src.port_id = port_id
	calculate_initial_stats()

/// Private
/// Calculates the initial stats of the shuttle
/datum/shuttle_data/proc/calculate_initial_stats()
	PRIVATE_PROC(TRUE)
	var/obj/docking_port/mobile/mobile_port = SSshuttle.getShuttle(port_id)
	for(var/area/shuttle_area as() in mobile_port.shuttle_areas)
		//Check turfs
		for(var/turf/T in shuttle_area)
			mass += 1
		//Handle shuttle engines
		for(var/obj/machinery/shuttle/engine/shuttle_engine in shuttle_area)
			register_thruster(shuttle_engine)
		//Handle shuttle shields
		for(var/obj/machinery/power/shuttle_shield_generator/shield_generator in shuttle_area)
			register_shield_generator(shield_generator)

//====================
// Shield Damage
//====================

/// Registers a shield generator
/datum/shuttle_data/proc/register_shield_generator(obj/machinery/power/shuttle_shield_generator/shield_generator)
	shield_health += shield_generator.shield_health
	registered_shield_generators += shield_generator
	RegisterSignal(shield_generator, COMSIG_PARENT_QDELETING, .proc/on_shield_qdel)
	RegisterSignal(shield_generator, COMSIG_SHUTTLE_SHIELD_HEALTH_CHANGE, .proc/shield_health_change)

/// Called when a shield generator is deleted
/datum/shuttle_data/proc/on_shield_qdel(obj/machinery/power/shuttle_shield_generator/shield_generator, force)
	registered_shield_generators -= shield_generator
	UnregisterSignal(shield_generator, COMSIG_PARENT_QDELETING)
	UnregisterSignal(shield_generator, COMSIG_SHUTTLE_SHIELD_HEALTH_CHANGE)

/// Deal damage to the shields
/datum/shuttle_data/proc/deal_damage(damage_amount)
	//Deal damage to the shields
	var/damage_left = damage_amount
	for(var/obj/machinery/power/shuttle_shield_generator/generator as() in registered_shield_generators)
		var/dealt_damage = min(damage_left, generator.shield_health)
		damage_left -= dealt_damage
		generator.give_shield(-dealt_damage)
		if(!damage_left)
			return

/datum/shuttle_data/proc/is_protected()
	return shield_health

/datum/shuttle_data/proc/shield_health_change(datum/source, old_health, new_health)
	var/delta_health = new_health - old_health
	shield_health += delta_health

//====================
// Fuel Consumption / Flight Processing
//====================

/datum/shuttle_data/proc/check_can_launch()
	//Check status of engines
	for(var/obj/machinery/shuttle/engine/shuttle_engine as() in registered_engines)
		shuttle_engine.update_engine()
	//Check thrust
	return thrust

//Consume fuel, check engine status
/datum/shuttle_data/proc/process_flight(thrust_amount = 0)
	var/fuel_usage = thrust_amount * ORBITAL_UPDATE_RATE_SECONDS * 0.01
	for(var/obj/machinery/shuttle/engine/shuttle_engine as() in registered_engines)
		if(!shuttle_engine.thruster_active)
			continue
		shuttle_engine.fireEngine()
		shuttle_engine.consume_fuel(fuel_usage)
		shuttle_engine.update_engine()

//Return true if shuttle can no longer fly
/datum/shuttle_data/proc/is_stranded()
	return !thrust

/datum/shuttle_data/proc/get_fuel()
	. = 0
	for(var/obj/machinery/shuttle/engine/shuttle_engine as() in registered_engines)
		if(!shuttle_engine.thruster_active)
			continue
		. += shuttle_engine.get_fuel_amount()

//====================
// Thrust handling
//====================

/// Called when a thruster is created on a shuttle
/datum/shuttle_data/proc/register_thruster(obj/machinery/shuttle/engine/source)
	if(source.thruster_active)
		thrust += source.thrust
		fuel_consumption += source.fuel_use
	registered_engines += source
	RegisterSignal(source, COMSIG_PARENT_QDELETING, .proc/on_thruster_qdel)
	RegisterSignal(source, COMSIG_SHUTTLE_ENGINE_STATUS_CHANGE, .proc/on_thruster_state_change)

/// Called when a thruster is deleted
/datum/shuttle_data/proc/on_thruster_qdel(obj/machinery/shuttle/engine/source, force)
	if(source.thruster_active)
		fuel_consumption -= source.fuel_use
		thrust -= source.thrust
	registered_engines -= source
	UnregisterSignal(source, COMSIG_PARENT_QDELETING)
	UnregisterSignal(source, COMSIG_SHUTTLE_ENGINE_STATUS_CHANGE)

/// Called when a shuttle thruster changes state
/datum/shuttle_data/proc/on_thruster_state_change(obj/machinery/shuttle/engine/source, old_state, new_state)
	if(old_state == new_state)
		return
	if(new_state)
		//Shuttle was turned on
		thrust += source.thrust
		fuel_consumption += source.fuel_use
	else
		//Shuttle was turned off
		thrust -= source.thrust
		fuel_consumption -= source.fuel_use

/datum/shuttle_data/proc/get_thrust_force()
	return thrust / mass
