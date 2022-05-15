AddCSLuaFile( 'cl_init.lua' )
AddCSLuaFile( 'shared.lua' )
include( 'shared.lua' )

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

OldTraceFunction = OldTraceFunction or util.TraceLine

RedirectionEntities = {}

function util.TraceLine( td )
	local tr = OldTraceFunction( td )
	if tr == nil then return end
	local reflectent = RedirectionEntities[ tr.Entity:EntIndex() ]
	if reflectent and reflectent:IsValid() and reflectent:GetPhysicsObject() and reflectent:GetPhysicsObject():IsValid() then
		local phys = reflectent:GetPhysicsObject()
		local startOffset = ( phys:WorldToLocalVector( td.start - reflectent:GetPos() ) ) / reflectent.Scale
		local endOffset = ( phys:WorldToLocalVector( td.endpos - reflectent:GetPos() ) ) / reflectent.Scale
		
		--debugoverlay.Line( startOffset, endOffset, 0.2, Color( 255, 255, 0 ), true )
		
		local newtd = {
			start = startOffset,
			endpos = endOffset,
			filter = td.filter,
			mask = td.mask,
			collisiongroup = td.collisiongroup,
			ignoreworld = td.ignoreworld,
			output = td.output,
		}
		return OldTraceFunction( newtd )
	else
		return tr
	end
end

function ENT:Initialize( )
	if #ents.FindByClass( "literallytheworld" ) > 1 then
		self:Remove()
	end
	
	self:SetModel( "models/hunter/blocks/cube025x025x025.mdl" )
	self.BaseClass.Initialize( self )
	self:DrawShadow( false )
	self:AddEFlags( EFL_FORCE_CHECK_TRANSMIT )
	
	self.worldSize = 16384
	self.Scale = 1/256*2
	
	self.MBounds, self.Bounds = game.GetWorld():GetModelBounds()
	self.MBounds, self.Bounds = self.MBounds * self.Scale, self.Bounds * self.Scale
	
	self:PhysicsInitBox( self.MBounds, self.Bounds )
	self:SetSolid( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:EnableCustomCollisions( true )
		
	self.gravityMagnitude = physenv.GetGravity():Length()
	
	RedirectionEntities[ self:EntIndex() ] = self
	
	self:PhysWake()
end

function ENT:Think()
	debugoverlay.BoxAngles( self:GetPos(), self.MBounds, self.Bounds, self:GetAngles(), 0.2, Color( 0, 255, 255, 4 ) )
	
	if self:GetPhysicsObject():IsValid() then
		physenv.SetGravity( self:GetPhysicsObject():WorldToLocalVector( Vector( 0, 0, -1 ) * self.gravityMagnitude) )
	
		oldVelocity = self.NowVelocity or Vector()
		self.NowVelocity = self:GetPhysicsObject():GetVelocity()
		
		self.Acceleration = self.NowVelocity - oldVelocity

	end
	
	self:NextThink( CurTime() )
	--[[ --enable for motion effect when moving the world around
	for k, v in ipairs( ents.GetAll() ) do
		if v and v:IsValid() and v:GetPhysicsObject():IsValid() then
			if v != self then
				local phys = v:GetPhysicsObject()
				phys:Wake()
				if self.Acceleration then
					phys:ApplyForceCenter( self:GetPhysicsObject():WorldToLocalVector( -self.Acceleration * phys:GetMass() / self.Scale ) )
				end
			end
		end
	end
	--]]--
	return true
end

function ENT:OnRemove()
	RedirectionEntities[ self:EntIndex() ] = nil
	
	physenv.SetGravity( Vector( 0, 0, -1 ) * self.gravityMagnitude )
end

local function translatePlayerToProperGrabPosition( ply, ent )
	if ent and ent:IsValid() then
		ply.IsInHackyGrabbingMode = true
		ply.LiteralWorldEntity = ent
		
		local phys = ent:GetPhysicsObject()
		
		if phys and phys:IsValid() then
			eyepos = ply:GetShootPos()
			eyeangles = ply:EyeAngles()
			
			local targOffset = ( phys:WorldToLocalVector( eyepos - ent:GetPos() ) ) / ent.Scale - ply:GetCurrentViewOffset()
			local targAngles = ent:WorldToLocalAngles( eyeangles )
			
			ply:SetPos( targOffset )
			ply:SetEyeAngles( targAngles )
			
			if targAngles.r != 0 then 
				ply:SendLua( "fixPlyRoll(LocalPlayer())" )
			end
		end
	end
end

local function returnPlayerToCorrectPosition( ply )
	if ply.IsInHackyGrabbingMode then
		ply.IsInHackyGrabbingMode = false
		
		local worldEnt = ply.LiteralWorldEntity
		
		if worldEnt and worldEnt:IsValid() then
			local phys = worldEnt:GetPhysicsObject()
			if phys and phys:IsValid() then
				eyepos = ply:GetShootPos()
				eyeangles = ply:EyeAngles()
				
				local targOffset = ( phys:LocalToWorldVector( eyepos ) ) * worldEnt.Scale + worldEnt:GetPos() - ply:GetCurrentViewOffset()
				local targAngles = worldEnt:LocalToWorldAngles( eyeangles )
				
				ply:SetPos( targOffset )
				ply:SetEyeAngles( targAngles )
				
				if targAngles.r != 0 then 
					ply:SendLua( "fixPlyRoll(LocalPlayer())" )
				end
			end
		end
		
		ply.LiteralWorldEntity = nil
		
	end
end

function ENT:PhysicsCollide( data, collider )
    util.ScreenShake( Vector(), data.Speed / 128, data.Speed, 1, 65535 )
    self:EmitSound( "Glass.ImpactSoft", nil, 20 + math.random( 0, 10 ), 2, CHAN_AUTO, 3 )
end

hook.Add( "PhysgunPickup", "ProxyPhysgun", function( ply, ent )
	if ent and ent:GetClass() == "literallytheworld" then
		local mins, maxs = ent.MBounds, ent.Bounds
		local hitvec, raynormal, fract = util.IntersectRayWithOBB( ply:GetShootPos(), Vector(), ent:GetPos(), ent:GetAngles(), mins, maxs )
		
		if hitvec then 
			translatePlayerToProperGrabPosition( ply, ent )
			return false
		end
	end
end )

hook.Add( "KeyRelease", "ProxyPhysgunEnd", function( ply, key ) 
	if key == IN_ATTACK then
		returnPlayerToCorrectPosition( ply )
	end
end )
