local N, A = ... -- Addon (N)ame, (A)ddon Table


A.CLASSES = A.CLASSES or {}
local R = A.CLASSES -- Class (R)epository


local C = "Fader" -- (C)lass Name
assert(R[C] == nil)
R[C] = {}
local E, P = {}, R[C] -- (E)ncapusalated Members, (P)ublic Members


-- constructor


function P.construct()
	local self = {
		events = R.EventDispatcher.construct(),
		groupPool = R.ObjectPool.construct(),
		--
		frame = CreateFrame("Frame"),
		activeGroups = {}, -- map
	}
	
	R.EventDispatcher.registerEvent(self.events, "FADE_STARTED")
	R.EventDispatcher.registerEvent(self.events, "FADE_STOPPED")
	R.EventDispatcher.registerEvent(self.events, "FADE_FINISHED")
	
	self.groupPool.constructFunc = E.constructAnimationGroup
	self.groupPool.constructObj = self
	self.groupPool.tearDownFunc = E.tearDownAnimationGroup
	self.groupPool.tearDownObj = self
	
	return self
end


-- private methods


function E.normalizeTime(value)
	if ( E.isPublicNumber(value) and value >= 0 ) then
		return value
	end
	return 0
end

function E.isPublicNumber(value)
	return not (issecretvalue and issecretvalue(value))
		and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function E.constructAnimationGroup(self)
	local group = self.frame:CreateFontString():CreateAnimationGroup()
	local animation = group:CreateAnimation("Alpha")
	
	group:SetToFinalAlpha(true)
	group:SetScript("OnPlay", function(...) E.animationGroup_onPlay(self, ...) end)
	group:SetScript("OnStop", function(...) E.animationGroup_onStop(self, ...) end)
	group:SetScript("OnFinished", function(...) E.animationGroup_onFinshed(self, ...) end)
	group:SetScript("OnUpdate", function(...) E.animationGroup_onUpdate(self, ...) end)
	group.animation = animation
	
	return group
end


function E.tearDownAnimationGroup(self, group)
	self.activeGroups[group.region] = nil
	group.region = nil
	group.snap = nil
	group.writeAlpha = nil
end


-- public methods


function P.addListener(self, event, handler, obj) R.EventDispatcher.addListener(self.events, event, handler, obj) end
function P.removeListener(self, event, obj) R.EventDispatcher.removeListener(self.events, event, obj) end
function P.isAListener(self, event, obj) R.EventDispatcher.isAListener(self.events, event, obj) end

function P.canAccess(self, region)
	if (issecretvalue and issecretvalue(region)) or type(region) ~= "table" then return false end
	local forbidden = region.IsForbidden and region:IsForbidden()
	return not (issecretvalue and issecretvalue(forbidden)) and not forbidden
end

function P.getAlpha(self, region)
	if not P.canAccess(self, region) then return nil end
	local alpha = self.frame.GetAlpha(region)
	if E.isPublicNumber(alpha) then return alpha end
end

function P.setAlpha(self, region, alpha)
	if not P.canAccess(self, region) or not E.isPublicNumber(alpha) then return false end
	self.frame.SetAlpha(region, alpha)
	return true
end


function P.fade(self, region, fromAlpha, toAlpha, duration, smoothing, startDelay, endDelay, writeAlpha)
	if not P.canAccess(self, region) or not E.isPublicNumber(toAlpha) then
		P.stopFade(self, region)
		return
	end
	if not E.isPublicNumber(fromAlpha) then fromAlpha = P.getAlpha(self, region) end
	local snap = fromAlpha == nil
	if snap then
		-- Preserve the delay, then apply the target without reading restricted alpha.
		fromAlpha = toAlpha
		duration = 0
	end
	duration = E.normalizeTime(duration)
	duration = duration == 0 and 0.001 or duration -- edge case: convert 0 to a millisecond
	smoothing = smoothing or "NONE"
	startDelay = E.normalizeTime(startDelay)
	endDelay = E.normalizeTime(endDelay)
	
	P.stopFade(self, region)
	
	local group = R.ObjectPool.acquire(self.groupPool)
	local animation = group.animation
	
	animation:SetFromAlpha(fromAlpha)
	animation:SetToAlpha(toAlpha)
	animation:SetDuration(duration)
	animation:SetSmoothing(smoothing)
	animation:SetStartDelay(startDelay)
	animation:SetEndDelay(endDelay)
	
	self.activeGroups[region] = group
	group.region = region
	group.snap = snap
	group.writeAlpha = writeAlpha
	
	group:Play()
end


function P.stopFade(self, region)
	if ( not P.isFading(self, region) ) then return end
	self.activeGroups[region]:Stop()
end


function P.isFading(self, region)
	return self.activeGroups[region] ~= nil
end


-- animationGroup events


function E.animationGroup_onPlay(self, group)
	local region = group.region
	local animation = group.animation
	local fromAlpha = animation:GetFromAlpha()
	local toAlpha = animation:GetToAlpha()
	local duration = animation:GetDuration()
	local smoothing = animation:GetSmoothing()
	local startDelay = animation:GetStartDelay()
	local endDelay = animation:GetEndDelay()
	
	R.EventDispatcher.dispatchEvent(self.events, "FADE_STARTED", region, fromAlpha, toAlpha, duration, smoothing, startDelay, endDelay)
end


function E.animationGroup_onStop(self, group)
	local region = group.region
	
	R.ObjectPool.release(self.groupPool, group)
	R.EventDispatcher.dispatchEvent(self.events, "FADE_STOPPED", region)
end


function E.animationGroup_onFinshed(self, group)
	local region = group.region
	local animation = group.animation
	local toAlpha = animation:GetToAlpha()
	
	local applied = (group.writeAlpha or P.setAlpha)(self, region, toAlpha)
	R.ObjectPool.release(self.groupPool, group)
	R.EventDispatcher.dispatchEvent(self.events, applied and "FADE_FINISHED" or "FADE_STOPPED", region, toAlpha)
end


function E.animationGroup_onUpdate(self, group)
	if not P.canAccess(self, group.region) then
		P.stopFade(self, group.region)
		return
	end
	if group.snap then return end
	local animation = group.animation
	local fromAlpha = animation:GetFromAlpha()
	local displacement = animation:GetToAlpha() - fromAlpha
	local alpha = fromAlpha + (displacement * animation:GetSmoothProgress())
	
	if group.writeAlpha then
		if not group.writeAlpha(self, group.region, alpha) then P.stopFade(self, group.region) end
	else
		self.frame.SetAlpha(group.region, alpha)
	end
end
