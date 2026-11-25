-- SPDX-License-Identifier: GPL-3.0-or-later
-- Coordinate-map behavior inspired by Manifold's saved-location map. No CE APIs.
local M={MAX_PINS=128}
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<100000 end
local function copy(p)
    assert(p and finite(p.x) and finite(p.y) and finite(p.z),"Invalid map position")
    return {x=p.x,y=p.y,z=p.z}
end
local function clamp(n,lo,hi)return math.max(lo,math.min(hi,n))end
local function overlap(a,b)
    return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h
end
function M.new()
    local V={pins={},trail={},live={},label_spots={},cx=0,cz=0,scale=1,target_scale=1,follow=false,labels=true}
    local next_pin=1
    function V:invalidate()
        self.key=nil;self.pins={};self.trail={};self.live={};self.player=nil
        self.selected=nil;self.group=nil;self.label_spots={};self.needs_fit=true
    end
    function V:update(snapshot)
        assert(type(snapshot.key)=="string","Missing map context")
        local p=copy(snapshot.position)
        if self.key~=snapshot.key then
            self:invalidate();self.key=snapshot.key;self.cx=p.x;self.cz=p.z
        end
        self.player=p;self.live={}
        for i,row in ipairs(snapshot.markers or {})do
            if i>128 then break end
            local ok,pos=pcall(copy,row.pos)
            if ok and type(row.id)=="string" then
                self.live[#self.live+1]={id=row.id,name=tostring(row.name or row.id),kind=row.kind or "target",pos=pos,key=self.key,region=row.region}
            end
        end
        local last=self.trail[#self.trail]
        local d=last and (p.x-last.x)^2+(p.z-last.z)^2+(p.y-last.y)^2
        if not last or d>=0.25^2 then
            p=copy(p);p.break_before=d and d>25^2 or false
            if #self.trail>=256 then table.remove(self.trail,1)end
            self.trail[#self.trail+1]=p
        end
        if self.follow then self.cx=self.player.x;self.cz=self.player.z end
    end
    function V:add_pin(name,pos)
        assert(self.key,"Enter the field first")
        assert(#self.pins<M.MAX_PINS,"Session pin limit reached (128)")
        local p=copy(pos)
        name=tostring(name or ""):gsub("[%z\1-\31]","")
        assert(utf8.len(name),"Invalid pin name")
        local cut=utf8.offset(name,65);if cut then name=name:sub(1,cut-1)end
        if not name:find("%S")then name="Pin "..next_pin end
        local id="pin:"..next_pin;next_pin=next_pin+1
        self.pins[#self.pins+1]={id=id,name=name,pos=p,key=self.key,kind="pin"}
        return id
    end
    function V:markers()
        local out={}
        if self.player then out[1]={id="player",name="You",kind="player",pos=self.player,key=self.key}end
        for _,list in ipairs({self.live,self.pins})do for _,point in ipairs(list)do out[#out+1]=point end end
        return out
    end
    function V:destination()
        for _,point in ipairs(self:markers())do
            if point.id==self.selected and point.id~="player" and point.key==self.key then
                return {key=point.key,pos=copy(point.pos),name=point.name,source="Map: "..point.name,kind=point.kind,id=point.id,region=point.region}
            end
        end
    end
    function V:remove_selected_pin()
        for i,point in ipairs(self.pins)do if point.id==self.selected then
            table.remove(self.pins,i);self.selected=nil;return true
        end end
        return false
    end
    function V:project(p,w,h)return w/2+(p.x-self.cx)*self.scale,h/2-(p.z-self.cz)*self.scale end
    function V:unproject(x,y,w,h)return {x=self.cx+(x-w/2)/self.scale,z=self.cz-(y-h/2)/self.scale}end
    function V:pan(dx,dy)
        self.cx=self.cx-dx/self.scale;self.cz=self.cz+dy/self.scale;self.follow=false
    end
    function V:zoom(factor)self.target_scale=clamp(self.target_scale*factor,0.02,40)end
    function V:animate(dt)
        local blend=1-math.exp(-math.max(0,math.min(dt,0.25))*24)
        self.scale=clamp(self.scale+(self.target_scale-self.scale)*blend,0.02,40)
    end
    function V:fit(w,h)
        local minx,maxx,minz,maxz
        for _,point in ipairs(self:markers())do
            local p=point.pos
            minx=math.min(minx or p.x,p.x);maxx=math.max(maxx or p.x,p.x)
            minz=math.min(minz or p.z,p.z);maxz=math.max(maxz or p.z,p.z)
        end
        if not minx then return end
        self.cx=(minx+maxx)/2;self.cz=(minz+maxz)/2;self.follow=false
        self.scale=clamp(math.min(math.max(1,w-60)/math.max(20,maxx-minx),math.max(1,h-60)/math.max(20,maxz-minz)),0.02,40)
        self.target_scale=self.scale;self.needs_fit=false
    end
    function V:grid_step()
        local desired=72/self.scale
        local base=10^math.floor(math.log(desired)/math.log(10))
        for _,n in ipairs({1,2,5,10})do if n*base>=desired then return n*base end end
    end
    function V:layout(w,h,measure)
        local groups,by_id={},{}
        local cluster_scale=2^math.floor(math.log(self.scale)/math.log(2))
        local cell=24/cluster_scale
        for _,point in ipairs(self:markers())do if point.kind~="player" then
            local id=math.floor(point.pos.x/cell)..":"..math.floor(point.pos.z/cell)
            local g=by_id[id]
            if not g then g={id=id,members={},wx=0,wz=0};groups[#groups+1]=g;by_id[id]=g end
            g.members[#g.members+1]=point;g.wx=g.wx+point.pos.x;g.wz=g.wz+point.pos.z
        end end
        table.sort(groups,function(a,b)return a.id<b.id end)
        local visible,blockers={},{{x=4,y=4,w=math.min(w-8,180),h=22}}
        if self.player then
            local x,y=self:project(self.player,w,h);blockers[#blockers+1]={x=x-8,y=y-8,w=16,h=16}
        end
        for _,g in ipairs(groups)do
            table.sort(g.members,function(a,b)return a.id<b.id end)
            g.x,g.y=self:project({x=g.wx/#g.members,z=g.wz/#g.members},w,h)
            if g.x>=-16 and g.y>=-16 and g.x<=w+16 and g.y<=h+16 then
                visible[#visible+1]=g;blockers[#blockers+1]={x=g.x-8,y=g.y-8,w=16,h=16}
            end
        end
        local labels,remembered={},{}
        for _,g in ipairs(groups)do remembered[g.id]=self.label_spots[g.id]end
        if self.labels then for _,g in ipairs(visible)do
            if #labels>=48 then break end
            local name=#g.members>1 and (#g.members.." locations") or g.members[1].name
            local tw,th=measure(name)
            local spots={{10,-th/2},{-tw-10,-th/2},{-tw/2,-th-10},{-tw/2,10},
                {10,-th-10},{-tw-10,-th-10},{10,10},{-tw-10,10}}
            local preferred=self.label_spots[g.id] or 1
            for attempt=0,7 do
                local index=attempt==0 and preferred or (attempt>=preferred and attempt+1 or attempt)
                local spot=spots[index]
                local rect={id=g.id,text=name,x=g.x+spot[1],y=g.y+spot[2],w=tw,h=th}
                local clear=rect.x>=4 and rect.y>=4 and rect.x+tw<=w-4 and rect.y+th<=h-4
                if clear then for _,b in ipairs(blockers)do if overlap(rect,b)then clear=false;break end end end
                if clear then for _,b in ipairs(labels)do if overlap(rect,b)then clear=false;break end end end
                if clear then labels[#labels+1]=rect;remembered[g.id]=index;break end
            end
        end end
        self.label_spots=remembered
        return {groups=visible,labels=labels}
    end
    function V:select_at(x,y,layout)
        self.selected=nil;self.group=nil
        local best,dist
        for _,g in ipairs(layout.groups)do
            local d=(g.x-x)^2+(g.y-y)^2
            if d<=14^2 and (not dist or d<dist)then best=g;dist=d end
        end
        if best then
            if #best.members==1 then self.selected=best.members[1].id else self.group=best.id end
        end
    end
    return V
end
return M
