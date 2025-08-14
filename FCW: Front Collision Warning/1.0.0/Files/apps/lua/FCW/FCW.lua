local settings = ac.storage{
    beepSound = true,
	beepVolume = 1,
    maxDistance = 50,
    PreliminaryWarning = 30, 
    SecondaryWarning = 15,
	detectionAngle = 5
}
local app_folder = ac.getFolder(ac.FolderID.ACApps) .. "/lua/FCW/"
local imgPath = app_folder .. "car_red.png"

local beepSound
local beepInitialized = false
local beepPlayed = false
local carVisible = false
local carBlinking = false
local blinkTimer = 0
local blinkDurationOn = 0.35
local blinkDurationOff = 0.35
local fading = 1
local firstshow = 0
local closestCarDistance = settings.maxDistance
local closestCarIndex = nil

local ANGLE_COS_THRESHOLD = math.cos(math.rad(settings.detectionAngle))

function script.windowSettings()
    ui.separator()

    if ui.checkbox("Audible warning", settings.beepSound) then
		settings.beepSound = not settings.beepSound
	end
	if ui.itemHovered() then ui.setTooltip("Enable or disable the Audible warning on Secondary Warning.") end

	if settings.beepSound then
		settings.beepVolume = ui.slider("Warning Volume", (settings.beepVolume or 1)*100, 0, 100, "%.0f%%")/100
		if settings.beepVolume == 0 then
			settings.beepSound = false
			settings.beepVolume = 1
		end
		if ui.itemHovered() then ui.setTooltip("Adjust the Warning Volume according to the car noise (engine, exhaust, etc). The sound might be very quiet around 0.010 ~ 0.100. Adjust to your preference.") end
	end
    settings.maxDistance = ui.slider("Max Distance", settings.maxDistance, 5, 500, "%.0f m")
	if ui.itemHovered() then ui.setTooltip("Maximum detection distance in meters.") end

    settings.PreliminaryWarning = ui.slider("Preliminary Warning", settings.PreliminaryWarning, settings.SecondaryWarning+1, settings.maxDistance, "%.0f m")
	if ui.itemHovered() then ui.setTooltip("Preliminary detection distance threshold (e.g., medium range). \n Secondary Warning <  Preliminary Warning <=  Max Distance") end

    settings.SecondaryWarning = ui.slider("Secondary Warning", settings.SecondaryWarning, 1, settings.PreliminaryWarning-1, "%.0f m")
	if ui.itemHovered() then ui.setTooltip("Close-range detection distance threshold (e.g., short range). \n Secondary Warning <  Preliminary Warning") end
	
	settings.detectionAngle = ui.slider("Detection angle", settings.detectionAngle, 1, 90, "%.0f°")
	if ui.itemHovered() then 
		ui.setTooltip("Detection angle in degrees. At 1° it only detects straight ahead, at 90° it detects completely sideways. Feel free to try. \n\n I recommend 5°.")
		ANGLE_COS_THRESHOLD = math.cos(math.rad(settings.detectionAngle))
	end
	
	ui.separator()
	ui.text("While the settings window is open, the icon remains visible.\nIf you adjust settings while driving within the Secondary\nWarning range, the icon does not flash.  To flash, close\nthe settings window and move the mouse away from the app window.")

end

local function ensureBeep()
    if not beepInitialized then
        beepSound = ui.MediaPlayer(nil, { rawOutput = true, use3D = false })
        beepSound:setLooping(false)
        beepSound:setSource(app_folder .. "beep.wav")
        beepSound:setVolume(settings.beepVolume or 1)
        beepInitialized = true
    end
end

local function playBeep()
    if settings.beepSound and not beepPlayed then
		ensureBeep()
		beepSound:setVolume(settings.beepVolume or 1)
        beepSound:play()
        beepPlayed = true
    end
end

local function dot(v1, v2)
    return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
end

local function normalize(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len > 0 then
        return { x = v.x / len, y = v.y / len, z = v.z / len }
    else
        return { x = 0, y = 0, z = 0 }
    end
end

function script.update(dt)
	local sim = ac.getSim()
    if not sim then return end

    local playerCar = ac.getCar(0)
    if not playerCar or not playerCar.position or not playerCar.look then
        carVisible, beepPlayed, carBlinking = false, false, false
        closestCarDistance, closestCarIndex = settings.maxDistance, nil
        return
    end

    local playerPos = playerCar.position
    local playerLook = playerCar.look

    closestCarDistance = settings.maxDistance
    closestCarIndex = nil

    for i = 1, sim.carsCount - 1 do
        local otherCar = ac.getCar(i)
        if otherCar and otherCar.position then
            local dx = otherCar.position.x - playerPos.x
            local dy = otherCar.position.y - playerPos.y
            local dz = otherCar.position.z - playerPos.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= closestCarDistance and dist <= settings.maxDistance then
                local toOtherNorm = normalize({ x = dx, y = dy, z = dz })
                if dot(playerLook, toOtherNorm) > ANGLE_COS_THRESHOLD then
                    closestCarDistance = dist
                    closestCarIndex = i
                end
            end
        end
    end

    if closestCarDistance <= settings.SecondaryWarning then
        carBlinking = true
        playBeep()
    elseif closestCarDistance <= settings.PreliminaryWarning then
        carVisible = true
        carBlinking = false
        beepPlayed = false
    else
        carVisible = false
        carBlinking = false
        beepPlayed = false
    end

    if carBlinking then
        blinkTimer = blinkTimer + dt
        if carVisible and blinkTimer >= blinkDurationOn then
            carVisible = false
            blinkTimer = 0
        elseif not carVisible and blinkTimer >= blinkDurationOff then
            carVisible = true
            blinkTimer = 0
        end
    else
        blinkTimer = 0
    end
end

function script.windowMain(dt)
	if carVisible then
		ui.image(imgPath, ui.availableSpace().x, ui.availableSpace().y)
	end

	if firstshow == 0 then
	
		elapsedTime = (elapsedTime or 0) + dt
		
		ui.image(imgPath, ui.availableSpace().x, ui.availableSpace().y)
		if elapsedTime >= 1 then
			firstshow = 1
		end
	end

    local windowFading = ac.windowFading()

    fading = math.applyLag(fading, false and 1 or 0, 0.9, dt)
    if fading < 0.01 then
        if windowFading < 1 then
            ui.pushStyleVarAlpha(1 - windowFading)
            
            local c = ui.getCursor()
            local s = ui.availableSpace()

            ui.image(imgPath, s.x, s.y)

            ui.beginOutline()
            for x = 0, 1 do
                for y = 0, 1 do
                    local p = vec2(c.x + x * s.x, c.y + y * s.y)
                    ui.pathLineTo(p + vec2(x == 0 and 20 or -20, 0))
                    ui.pathLineTo(p)
                    ui.pathLineTo(p + vec2(0, y == 0 and 20 or -20))
                    ui.pathStroke(rgbm.colors.white, false, 1)
                end
            end
            ui.endOutline(rgbm.colors.black, 1)
        end
        return
    end
end



