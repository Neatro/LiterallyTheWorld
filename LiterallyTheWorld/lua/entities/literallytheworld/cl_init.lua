include("shared.lua")
ENT.RenderGroup = RENDERGROUP_BOTH

local function resetstencil()
	render.SetStencilWriteMask( 0xFF )
	render.SetStencilTestMask( 0xFF )
	render.SetStencilReferenceValue( 0 )
	render.SetStencilCompareFunction( STENCIL_ALWAYS )
	render.SetStencilPassOperation( STENCIL_KEEP )
	render.SetStencilFailOperation( STENCIL_KEEP )
	render.SetStencilZFailOperation( STENCIL_KEEP )
	render.ClearStencil()
end

local dontDrawSky = false
local drawingWorld = false
local rt = rt
local WorldRenderMaterial = WorldRenderMaterial

--creates and also fixes the screenmaterial
local function fixScreenMaterial()

	rt = GetRenderTarget( "StencilledworldRT", ScrW(), ScrH() )
	--Magic texture
	WorldRenderMaterial = CreateMaterial( "Stencilledworld", "UnlitGeneric", {
		["$basetexture"] = "concrete/concrete_sidewalk001b", 
	}) 
	WorldRenderMaterial:SetInt( "$flags", 16 + 32 + 256 )
	WorldRenderMaterial:SetInt( "$model", 1 )
	WorldRenderMaterial:SetTexture( "$basetexture", rt )
	
	--Cube texture, invisible
	CubeMaterial = CreateMaterial( "StencilledworldCube", "UnlitGeneric", {
		["$basetexture"] = "concrete/concrete_sidewalk001b", 
	}) 
	CubeMaterial:SetInt( "$flags", 16 + 32 )
	CubeMaterial:SetInt( "$model", 1 )
	CubeMaterial:SetTexture( "$basetexture", "color/white" )
	CubeMaterial:SetFloat( "$alpha", 0 )
	
end

--Detour for traceline
OldTraceFunction = OldTraceFunction or util.TraceLine

RedirectionEntities = {}
--[[ --will fix trace detour sooner or later
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
]]--
function ENT:Initialize()

	RedirectionEntities[ self:EntIndex() ] = self
	
	self.Material = ""
	
	self:DrawShadow( false )
	
	self.worldSize = 16384
	self.Scale = 1/256*2
	
	self.rendersize = self.worldSize * self.Scale
	
	self.MBounds, self.Bounds = game.GetWorld():GetModelBounds()
	self.MBounds, self.Bounds = self.MBounds * self.Scale, self.Bounds * self.Scale

	self:SetRenderBounds( self.MBounds, self.Bounds )
	
	self.Matrix = Matrix()
	--strange fix
	self:SetColor( Color( 0, 0, 0, 0 ) )
	self:SetMaterial( "Models/effects/vol_light001" )
	
	self:PhysicsInitBox( self.MBounds, self.Bounds )
	self:SetSolid( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:EnableCustomCollisions( true )
	
	fixScreenMaterial()
	
	local entindex = self:EntIndex()
	
	--Hacky method to completely get rid of the skybox
	hook.Add( "PreDrawSkyBox", "MiniWorldNoSky", function() 
		if self.dontDrawSky then
			return true
		end
	end )

	hook.Add( "CalcView", "WorldDrawAdjust", function( ply, pos, angles, fov )
		if self.dontDrawSky then
			local view = {
				origin = pos,
				angles = angles,
				fov = fov,
				drawviewer = true
			}
			return view
		end
	end )
	
	--fog fix
	hook.Add( "SetupWorldFog", "WorldDrawFogAdjust", function( ply, pos, angles, fov )
		if self.dontDrawSky then
			render.FogMode( MATERIAL_FOG_NONE )
			return true
		end
	end )

	local currentEntity = Entity( entindex )
	hook.Add( "RenderScene", "WorldRenderThing", function( pos, ang, fov )
		if drawingWorld then
			return true
		end
		
		local eyepos, eyeangles = pos, ang
		if currentEntity and currentEntity:IsValid() then
			drawingWorld = true
				
			render.PushRenderTarget( rt )
				
				cam.Start3D()
				
				render.Clear( 0, 0, 0, 0, true, true )
				
				resetstencil()
				-- Enable stencils
				render.SetStencilEnable( true )
				render.SetStencilReferenceValue( 1 )
				render.SetStencilCompareFunction( STENCIL_ALWAYS )
				render.SetStencilPassOperation( STENCIL_REPLACE )
				render.SetStencilFailOperation( STENCIL_KEEP )
				
				local offset = ( eyepos / self.Scale - currentEntity:GetPos() / self.Scale )
				offset = currentEntity:WorldToLocal( offset )
				local offset2 = currentEntity:WorldToLocal( Vector() )
				
				--halo fix
				local oldHaloFunction = halo.Add
				halo.Add = function() end

				--sky
				self.dontDrawSky = true
				
				render.OverrideDepthEnable( true, true )
				render.RenderView( {
					origin = offset - offset2, 
					angles = currentEntity:WorldToLocalAngles( eyeangles ),
					x = x, y = y,
					w = w, h = h,
					drawhud = false,
					drawviewmodel = false,
					zfar = 32768 / self.Scale,
					znear = 1 / self.Scale,
					fov = fov
				} )
				render.OverrideDepthEnable( false, false )
				
				--sky end
				self.dontDrawSky = false

				--halo fix end
				halo.Add = oldHaloFunction
				
				--draw world
				render.SetStencilCompareFunction( STENCIL_EQUAL )
				render.SetStencilPassOperation( STENCIL_REPLACE )
				render.SetStencilReferenceValue( 0 )
				
				render.ClearBuffersObeyStencil( 0, 0, 0, 0, false )
				
				render.SetStencilEnable( false )
				
				cam.End3D()
				
			render.PopRenderTarget()
				
			drawingWorld = false
		end
		
		return false
	end )
end

function ENT:Think()
	--physics fix
	local physobj = self:GetPhysicsObject()
	if physobj:IsValid() then
		physobj:SetPos( self:GetPos() )
		physobj:SetAngles( self:GetAngles() )
		physobj:EnableMotion( false )
		physobj:Sleep()
	end
end

local drawingEnt

function ENT:Draw()
	
	if halo.RenderedEntity() == self then 
		render.SetColorMaterial()
		render.DrawBox( self:GetPos(), self:GetAngles(), self.MBounds, self.Bounds, Color( 127, 127, 191 ) )
		
		return 
	end
	
	--dont draw itself tiny, otherwise ded
	if drawingEnt or drawingWorld then 
		render.SetColorMaterial()
		render.DrawBox( self:GetPos(), self:GetAngles(), self.MBounds, self.Bounds, Color( 127, 127, 191 ) )
				
		return 
	end
	
	if WorldRenderMaterial then
		
		render.SetStencilEnable( true )
		
		resetstencil()
		
		render.ClearStencil()
		render.SetStencilWriteMask( 0x1  )
		render.SetStencilTestMask( 0x1  )
		render.SetStencilReferenceValue( 1 )
		render.SetStencilCompareFunction( STENCIL_ALWAYS )
		render.SetStencilPassOperation( STENCIL_REPLACE )
		render.SetStencilFailOperation( STENCIL_KEEP )
		render.SetStencilZFailOperation( STENCIL_KEEP )

		--draw box
		render.SetMaterial( CubeMaterial ) --Material( "phoenix_storms/glass" )
		render.OverrideDepthEnable( false, false )
		render.DrawBox( self:GetPos(), self:GetAngles(), self.Bounds, self.MBounds )
		render.DrawBox( self:GetPos(), self:GetAngles(), self.MBounds, self.Bounds )
		render.OverrideDepthEnable( false, false )
		
		--draw screentexture
		render.SetStencilCompareFunction( STENCIL_EQUAL )
		
		render.SetMaterial( WorldRenderMaterial )
		render.DrawScreenQuadEx( 0, 0, ScrW(), ScrH() )
	
		render.SetStencilEnable( false )
		
	end

	debugoverlay.BoxAngles( self:GetPos(), self.MBounds, self.Bounds, self:GetAngles(), 0.05, Color( 255, 255, 0, 1 ) )

end

function ENT:DrawTranslucent()
	
end

function ENT:OnRemove()
	local entindex = self:EntIndex()
	--clean client resources
	timer.Simple(0, function()
		if not IsValid( self ) then
		
			hook.Remove( "PreDrawSkyBox", "MiniWorldNoSky" )
			hook.Remove( "CalcView", "WorldDrawAdjust" )
			hook.Remove( "RenderScene", "WorldRenderThing" )
			
			RedirectionEntities[ self:EntIndex() ] = nil
			
		end 
	end)
	
end

function fixPlyRoll( ply )
	ply.rollMultiplierCounter = 60
	timer.Create( CurTime().."FixPlyRoll", 1/66, 30, function() 
		local eyeangles = ply:EyeAngles()
		
		ply.rollMultiplierCounter = ply.rollMultiplierCounter - 1
		
		ply:SetEyeAngles( Angle( eyeangles.p, eyeangles.y, eyeangles.r * ply.rollMultiplierCounter / 60 ) ) 
	end )
end
