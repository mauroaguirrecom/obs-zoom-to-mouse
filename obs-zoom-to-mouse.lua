-- OBS Zoom to Mouse (v2.5 - Modificado con Zoom Asimétrico)
-- Compatible con OBS 30+ y Windows (FFI). No requiere Python.
-- Inspirado en Cursorful.com — clics automáticos, paneos suaves y zoom out por inactividad.

local obs = obslua
local ffi = require("ffi")
local VERSION = "2.5-Mod"
local CROP_FILTER_NAME = "obs-zoom-to-mouse-crop"

-- =========================================================
-- VARIABLES GLOBALES
-- =========================================================
local source_name = ""
local source = nil
local crop_filter = nil
local crop_filter_settings = nil
local crop_filter_info_orig = { x = 0, y = 0, w = 1920, h = 1080 }
local crop_filter_info = { x = 0, y = 0, w = 0, h = 0 }

-- MODIFICADO: Separado en Ancho (W) y Alto (H)
local zoom_value_w = 2
local zoom_value_h = 2
local zoom_speed = 0.12
local zoom_time = 0
local zoom_target = nil
local is_anim_timer_running = false
local auto_loop_timer_running = false
local auto_loop_interval_ms = 33 -- ~30 FPS

local auto_pan_speed = 0.08
local idle_timeout_ms = 3000
local debug_logs = false

local last_click_state = false
local last_click_time = 0
local last_action_time = 0

local ZoomState = { None = 0, ZoomingIn = 1, ZoomingOut = 2, ZoomedIn = 3 }
local zoom_state = ZoomState.None

-- =========================================================
-- FFI (Windows)
-- =========================================================
if ffi.os == "Windows" then
    ffi.cdef[[
        typedef struct { long x; long y; } POINT, *LPPOINT;
        bool GetCursorPos(LPPOINT lpPoint);
        short GetAsyncKeyState(int vKey);
    ]]
end
local VK_LBUTTON = 0x01

-- =========================================================
-- UTILIDADES
-- =========================================================
local function log(msg)
    if debug_logs then obs.script_log(obs.OBS_LOG_INFO, "[ZoomToMouse] " .. tostring(msg)) end
end

local function clamp(a,b,v) return math.max(a, math.min(b, v)) end
local function lerp(a,b,t) return a*(1-t)+b*t end
local function ease_in_out01(t)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    t = t * 2
    if t < 1 then return 0.5 * t * t * t end
    t = t - 2
    return 0.5 * (t * t * t + 2)
end

local function now_ms()
    return obs.os_gettime_ns() / 1000000
end

-- =========================================================
-- ENTRADA DE RATÓN
-- =========================================================
local function get_mouse_pos()
    local m = { x = 0, y = 0 }
    if ffi.os == "Windows" then
        local pt = ffi.new("POINT[1]")
        if ffi.C.GetCursorPos(pt) then
            m.x = tonumber(pt[0].x)
            m.y = tonumber(pt[0].y)
        end
    end
    return m
end

local function mouse_clicked_edge()
    if ffi.os ~= "Windows" then return false end
    local state = tonumber(ffi.C.GetAsyncKeyState(VK_LBUTTON))
    local pressed = state < 0
    local edge = pressed and not last_click_state
    last_click_state = pressed
    return edge
end

-- =========================================================
-- MANEJO DE FUENTES Y FILTROS
-- =========================================================
local function release_resources()
    if crop_filter_settings then obs.obs_data_release(crop_filter_settings) end
    if crop_filter then obs.obs_source_release(crop_filter) end
    if source then obs.obs_source_release(source) end
    crop_filter_settings, crop_filter, source = nil, nil, nil
end

local function get_display_source_auto()
    local sources = obs.obs_enum_sources()
    if sources then
        for _, s in ipairs(sources) do
            local id = obs.obs_source_get_id(s)
            if id == "monitor_capture" or id == "display_capture" then
                local name = obs.obs_source_get_name(s)
                obs.source_list_release(sources)
                return name
            end
        end
        obs.source_list_release(sources)
    end
    return nil
end

local function ensure_crop_filter()
    if not source then return false end
    if crop_filter and crop_filter_settings then return true end

    local f = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
    if f then
        crop_filter = f
        crop_filter_settings = obs.obs_source_get_settings(f)
        return true
    end

    local settings = obs.obs_data_create()
    local bw, bh = obs.obs_source_get_base_width(source), obs.obs_source_get_base_height(source)
    obs.obs_data_set_bool(settings, "relative", false)
    obs.obs_data_set_int(settings, "left", 0)
    obs.obs_data_set_int(settings, "top", 0)
    obs.obs_data_set_int(settings, "cx", bw)
    obs.obs_data_set_int(settings, "cy", bh)

    local newf = obs.obs_source_create_private("crop_filter", CROP_FILTER_NAME, settings)
    obs.obs_source_filter_add(source, newf)
    crop_filter, crop_filter_settings = newf, settings
    crop_filter_info = { x = 0, y = 0, w = bw, h = bh }
    crop_filter_info_orig = { x = 0, y = 0, w = bw, h = bh }
    log("Crop filter created for " .. obs.obs_source_get_name(source))
    return true
end

local function update_source()
    release_resources()
    if not source_name or source_name == "" or source_name == "none" then
        source_name = get_display_source_auto() or ""
        if source_name == "" then
            obs.script_log(obs.OBS_LOG_WARNING, "[ZoomToMouse] No display capture found.")
            return
        end
    end
    source = obs.obs_get_source_by_name(source_name)
    if not source then
        obs.script_log(obs.OBS_LOG_WARNING, "[ZoomToMouse] Source not found: " .. source_name)
        return
    end
    ensure_crop_filter()
end

-- =========================================================
-- CÁLCULO DE ZOOM
-- =========================================================
-- MODIFICADO: Ya no recibe 'zoom_to', usa las variables globales
local function compute_target_crop()
    if not crop_filter_info_orig then return nil end
    local mouse = get_mouse_pos()
    local sw, sh = crop_filter_info_orig.w, crop_filter_info_orig.h
    if sw == 0 or sh == 0 then sw, sh = 1920, 1080 end

    local mx = clamp(0, sw, mouse.x)
    local my = clamp(0, sh, mouse.y)

    -- MODIFICADO: Usa zoom_value_w y zoom_value_h
    local nw, nh = math.floor(sw / zoom_value_w), math.floor(sh / zoom_value_h)
    local x, y = mx - nw / 2, my - nh / 2
    x, y = clamp(0, sw - nw, x), clamp(0, sh - nh, y)

    return { crop = { x = x, y = y, w = nw, h = nh } }
end

local function apply_crop(crop)
    if not crop_filter or not crop_filter_settings then return end
    obs.obs_data_set_int(crop_filter_settings, "left", math.floor(crop.x))
    obs.obs_data_set_int(crop_filter_settings, "top", math.floor(crop.y))
    obs.obs_data_set_int(crop_filter_settings, "cx", math.floor(crop.w))
    obs.obs_data_set_int(crop_filter_settings, "cy", math.floor(crop.h))
    obs.obs_source_update(crop_filter, crop_filter_settings)
end

-- =========================================================
-- ANIMACIÓN
-- =========================================================
local function anim_timer()
    if not zoom_target then return end
    zoom_time = zoom_time + zoom_speed
    local t = ease_in_out01(zoom_time)
    crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, t)
    crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, t)
    crop_filter_info.w = lerp(crop_filter_info.w, zoom_target.crop.w, t)
    crop_filter_info.h = lerp(crop_filter_info.h, zoom_target.crop.h, t)
    apply_crop(crop_filter_info)

    if zoom_time >= 1 then
        if zoom_state == ZoomState.ZoomingIn then zoom_state = ZoomState.ZoomedIn end
        if zoom_state == ZoomState.ZoomingOut then zoom_state = ZoomState.None end
        obs.timer_remove(anim_timer)
        is_anim_timer_running = false
    end
end

-- =========================================================
-- EVENTOS AUTOMÁTICOS (CLICK, PAN, IDLE)
-- =========================================================
local function auto_loop()
    local now = now_ms()

    -- clic -> zoom
    if mouse_clicked_edge() then
        last_click_time, last_action_time = now, now
        if zoom_state == ZoomState.ZoomedIn then
            zoom_target = compute_target_crop() -- MODIFICADO
            zoom_time = 0
            zoom_state = ZoomState.ZoomingIn
        else
            zoom_state = ZoomState.ZoomingIn
            zoom_time = 0
            zoom_target = compute_target_crop() -- MODIFICADO
        end
        if not is_anim_timer_running then
            is_anim_timer_running = true
            obs.timer_add(anim_timer, 16)
        end
    end

    -- pan automático
    if zoom_state == ZoomState.ZoomedIn and crop_filter_info then
        local target = compute_target_crop() -- MODIFICADO
        if target then
            crop_filter_info.x = lerp(crop_filter_info.x, target.crop.x, auto_pan_speed)
            crop_filter_info.y = lerp(crop_filter_info.y, target.crop.y, auto_pan_speed)
            apply_crop(crop_filter_info)
        end
    end

    -- timeout -> zoom out
    -- [[ CAMBIO 1: Añadido "idle_timeout_ms > 0" para desactivar si es 0 ]]
    if idle_timeout_ms > 0 and zoom_state == ZoomState.ZoomedIn and now - last_action_time > idle_timeout_ms then
        zoom_state = ZoomState.ZoomingOut
        zoom_time = 0
        zoom_target = { crop = crop_filter_info_orig }
        if not is_anim_timer_running then
            is_anim_timer_running = true
            obs.timer_add(anim_timer, 16)
        end
        last_action_time = now
    end
end

-- =========================================================
-- FUNCIONES PRINCIPALES
-- =========================================================
function on_toggle_zoom(pressed)
    if not pressed or not source then return end
    if zoom_state == ZoomState.ZoomedIn then
        zoom_state = ZoomState.ZoomingOut
        zoom_time = 0
        zoom_target = { crop = crop_filter_info_orig }
    else
        zoom_state = ZoomState.ZoomingIn
        zoom_time = 0
        zoom_target = compute_target_crop() -- MODIFICADO
    end
    if not is_anim_timer_running then
        is_anim_timer_running = true
        obs.timer_add(anim_timer, 16)
    end
end

-- =========================================================
-- OBS UI Y CONFIGURACIÓN
-- =========================================================
function script_properties()
    local props = obs.obs_properties_create()
    local src_list = obs.obs_properties_add_list(props, "source", "Zoom Source",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)

    obs.obs_property_list_add_string(src_list, "<Auto>", "")
    local sources = obs.obs_enum_sources()
    if sources then
        for _, s in ipairs(sources) do
            local name = obs.obs_source_get_name(s)
            obs.obs_property_list_add_string(src_list, name, name)
        end
        obs.source_list_release(sources)
    end

    -- MODIFICADO: Renombrado a 'Ancho'
    obs.obs_properties_add_float(props, "zoom_value_w", "Zoom Factor (Ancho)", 1, 10, 0.5)
    -- AÑADIDO: Nuevo factor de zoom para 'Alto'
    obs.obs_properties_add_float(props, "zoom_value_h", "Zoom Factor (Alto)", 1, 10, 0.5)

    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.01, 0.5, 0.01)
    
    -- [[ CAMBIO 2: Aumentado el límite a 3,600,000 (1 hora), mínimo a 0, y actualizada la etiqueta ]]
    obs.obs_properties_add_int(props, "idle_timeout_ms", "Idle Timeout (ms) [0 = Desactivado]", 0, 3600000, 500)
    
    obs.obs_properties_add_float(props, "auto_pan_speed", "Auto Pan Speed", 0.01, 0.5, 0.01)
    obs.obs_properties_add_bool(props, "debug_logs", "Enable debug logging")
    obs.obs_properties_add_button(props, "quick_start_btn", "🔘 Iniciar Zoom", function() on_toggle_zoom(true) return true end)
    return props
end

function script_update(settings)
    local old = source_name
    source_name = obs.obs_data_get_string(settings, "source")
    
    -- MODIFICADO: Renombrado a _w
    zoom_value_w = obs.obs_data_get_double(settings, "zoom_value_w") or zoom_value_w
    -- AÑADIDO: _h
    zoom_value_h = obs.obs_data_get_double(settings, "zoom_value_h") or zoom_value_h
    
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed") or zoom_speed
    idle_timeout_ms = obs.obs_data_get_int(settings, "idle_timeout_ms") or idle_timeout_ms
    auto_pan_speed = obs.obs_data_get_double(settings, "auto_pan_speed") or auto_pan_speed
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs") or debug_logs
    if source_name ~= old then update_source() end
end

function script_defaults(settings)
    -- MODIFICADO: Renombrado a _w
    obs.obs_data_set_default_double(settings, "zoom_value_w", 2)
    -- AÑADIDO: _h
    obs.obs_data_set_default_double(settings, "zoom_value_h", 2)
    
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.12)
    obs.obs_data_set_default_int(settings, "idle_timeout_ms", 3000)
    obs.obs_data_set_default_double(settings, "auto_pan_speed", 0.08)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
end

function script_description()
    return "Zoom to Mouse v2.5 — Clic automático, paneo y zoom out por inactividad. (Zoom Ancho/Alto separado)"
end

function script_load(settings)
    update_source()
    obs.timer_add(auto_loop, auto_loop_interval_ms)
end

function script_unload()
    obs.timer_remove(auto_loop)
    if is_anim_timer_running then obs.timer_remove(anim_timer) end
    release_resources()
end
