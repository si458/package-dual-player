gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

util.no_globals()

local myconfig = {}

local function image(file, duration)
    local img, ends
    return {
        prepare = function()
            img = resource.load_image{
                file = file,
            }
        end;
        start = function()
            ends = sys.now() + duration
        end;
        draw = function(pos)
            util.draw_correct(img, pos.x1, pos.y1, pos.x2, pos.y2)
            return sys.now() <= ends
        end;
        dispose = function()
            img:dispose()
        end;
    }
end

local function video(file, duration)
    local vid, ends
    return {
        prepare = function()
            print "video prepare"
            vid = resource.load_video{
                file = file,
                paused = true,
                raw = true,
            }
        end;
        start = function()
            print "video start"
            ends = sys.now() + duration
        end;
        draw = function(pos)
            local state, width, height = vid:state()
            if state == "paused" then
                local x1, y1, x2, y2 = util.scale_into(pos.x2-pos.x1, pos.y2-pos.y1, width, height)
                vid:place(pos.x1+x1, pos.y1+y1, pos.x1+x2, pos.y1+y2):layer(1):start()
            end
            return sys.now() <= ends -- and (state == "paused" or state == "loaded")
        end;
        dispose = function()
            print "video dispose"
            vid:dispose()
        end;
    }
end

local function Runner(scheduler, pos)
    local cur, nxt, old

    local function prepare()
        assert(not nxt)
        nxt = scheduler.get_next()
        nxt.prepare()
    end
    local function down()
        assert(not old)
        old = cur
        cur = nil
    end
    local function switch()
        assert(nxt)
        cur = nxt
        cur.start()
        nxt = nil
    end
    local function dispose()
        old.dispose()
        old = nil
    end

    local function tick()
        if not nxt then
            prepare()
        end
        if old then
            dispose()
        end
        if not cur then
            switch()
        end
        if not cur.draw(pos) then
            down()
        end
    end

    return {
        tick = tick;
    }
end

local function cycled(items, offset)
    if #items == 0 then
        return nil, 0
    end
    offset = offset % #items + 1
    return items[offset], offset
end

local function Scheduler()
    local items = {}
    local offset = 0

    local function update(playlist)
        local new_items = {}
        for _, item in ipairs(playlist) do
            new_items[#new_items+1] = {
                file = resource.open_file(item.asset.asset_name),
                type = item.asset.type,
                duration = item.duration,
            }
        end
        items = new_items

        -- uncomment if a playlist change should start that playlist from the beginning
        -- offset = 0
    end

    local function get_next()
        local item
        print("next item?", offset, #items)
        item, offset = cycled(items, offset)
        pp(item)
        print(offset)
        item = item or { -- fallback?
            file = resource.open_file("empty.png"),
            type = "image",
            duration = 1,
        }
        return ({
            image = image,
            video = video,
        })[item.type](item.file:copy(), item.duration)
    end

    return {
        update = update,
        get_next = get_next,
    }
end

local playlist_1 = Scheduler()
local playlist_2 = Scheduler()

util.json_watch("config.json", function(config)
    print "my config.json changed"
    myconfig = config
    playlist_1.update(config.playlist_1)
    playlist_2.update(config.playlist_2)
end)

local runner_1 = Runner(playlist_1, {
    x1 = 0,
    y1 = 0,
    x2 = WIDTH/2,
    y2 = HEIGHT,
})

local runner_2 = Runner(playlist_2, {
    x1 = WIDTH/2,
    y1 = 0,
    x2 = WIDTH,
    y2 = HEIGHT,
})

local st = util.screen_transform(0)
st()

function node.render()
    print myconfig
    -- gl.clear(0,0,0,1)
    -- local st = util.screen_transform(myconfig.rotation)
    -- st()
    print "node.render"
    runner_1.tick()
    runner_2.tick()
end
