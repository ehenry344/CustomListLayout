--@author BostonWhaIer
--@created 11/27/2024
--@updated 12/28/2024

--[[
Custom UIListLayout implementation

Benefits
- More granularity provided through the ability to manipulate the position of instances under its jurisdiction (can offset certain instances in the list)
- Support for dynamically updating the size of instances when its parent container is resized
]]

--!strict

type FillDirection = "Horizontal" | "Vertical"
type SortOrder = "LayoutOrder" | "Name"
type HorizontalAlignment = "Left" | "Right" | "Center"
type VerticalAlignment = "Top" | "Bottom" | "Center"

export type CustomListLayoutConfig = {
	Padding: UDim?,
	FillDirection: FillDirection?,
	SortOrder: SortOrder?,
	HorizontalAlignment: HorizontalAlignment?,
	VerticalAlignment: VerticalAlignment?,
}

type ListLayoutProto = {
	__index: ListLayoutProto,
	
	new: (adornee: GuiObject, config: CustomListLayoutConfig)->ListLayout,
	
	Destroy: (ListLayout)->(), 
	
	_hookAdornee: (ListLayout)->(),
	_hookChild: (ListLayout, GuiObject)->(),
	_unhookChild: (ListLayout, GuiObject)->(),
	_getInstances: (ListLayout)->{GuiObject},
	_positionInstances: (ListLayout)->()
}

type ListLayout = typeof(setmetatable({} :: {
	_adornee: GuiObject,
	_connections: {[GuiObject]: {RBXScriptConnection}},
		
	Padding: UDim, 
	FillDirection: FillDirection,
	SortOrder: SortOrder,
	HorizontalAlignment: HorizontalAlignment,
	VerticalAlignment: VerticalAlignment,
}, {} :: ListLayoutProto))

local CustomListLayout: ListLayoutProto = {} :: ListLayoutProto
CustomListLayout.__index = CustomListLayout

function CustomListLayout.new(adornee: GuiObject, config: CustomListLayoutConfig): ListLayout
	if adornee:FindFirstChildOfClass("UIListLayout") then
		error("Incompatiblity Err: cannot apply CustomListLayout to instance with UIListLayout")
	end
	
	local self = setmetatable({
		_adornee = adornee, 
		_connections = {},
		
		Padding = config.Padding or UDim.new(0, 0), 
		FillDirection = config.FillDirection or "Vertical" :: FillDirection,
		SortOrder = config.SortOrder or "LayoutOrder" :: SortOrder,
		HorizontalAlignment = config.HorizontalAlignment or "Left" :: HorizontalAlignment,
		VerticalAlignment = config.VerticalAlignment or "Top" :: VerticalAlignment, 
	}, CustomListLayout)
		
	self:_hookAdornee()
	
	return self
end

function CustomListLayout:Destroy()
	for instance, connectionTable in self._connections do
		for _, connection in connectionTable do
			connection:Disconnect()
		end
		
		self._connections[instance] = nil
	end
	
	setmetatable(self, nil)
	self = nil
	-- gotta figure out how to not make this leak memory (aka setting everything in the table to nil to allow gc), typechecking is giving me issues with that :P
end

function CustomListLayout:_hookChild(child: GuiObject)
	self._connections[child] = {}

	table.insert(self._connections[child], child:GetPropertyChangedSignal("Visible"):Connect(function()
		self:_positionInstances()
	end))
	
	table.insert(self._connections[child], child:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_positionInstances()
	end))
	
	table.insert(self._connections[child], child:GetPropertyChangedSignal("LayoutOrder"):Connect(function()
		self:_positionInstances()
	end))
end

function CustomListLayout:_unhookChild(child: GuiObject)
	if self._connections[child] then
		for _, connection in ipairs(self._connections[child]) do
			connection:Disconnect()
		end
		
		self._connections[child] = nil
	end
end

function CustomListLayout:_hookAdornee()
	self._connections[self._adornee] = {}
	
	table.insert(self._connections[self._adornee], self._adornee.Destroying:Connect(function()
		self:Destroy()
	end))
	
	table.insert(self._connections[self._adornee], self._adornee.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			self:_hookChild(child)
			
			self:_positionInstances()
		end
	end))
	
	table.insert(self._connections[self._adornee], self._adornee.ChildRemoved:Connect(function(child)
		if child:IsA("GuiObject") then
			self:_unhookChild(child)

			self:_positionInstances()
		end
	end))
	
	for _, child in ipairs(self:_getInstances()) do
		self:_hookChild(child)
	end
	
	self:_positionInstances()
end

function CustomListLayout:_getInstances()
	local guiInstances = {}
	
	for _, v in pairs(self._adornee:GetChildren()) do
		if v:IsA("GuiObject") and v.Visible then
			table.insert(guiInstances, v) 
		end 
	end
	
	return guiInstances
end

function CustomListLayout:_positionInstances()	
	local children = self:_getInstances()
	
	-- in the future perhaps clean this up so we dont need to sort, we just position elements based off their numbers
	
	table.sort(children, function(a, b)
		if self.SortOrder == "LayoutOrder" then
			return a.LayoutOrder < b.LayoutOrder
		else
			return a.Name < b.Name
		end
	end)
	
	local adorneeWidth = self._adornee.AbsoluteSize.X
	local adorneeHeight = self._adornee.AbsoluteSize.Y
		
	if self.FillDirection == "Horizontal" then
		local absolutePadding = self.Padding.Offset + (adorneeWidth * self.Padding.Scale)
		
		local xOffset = 0 -- default / left align
		
		-- get content size
		local contentSize = 0
		for i, child in children do
			contentSize += child.AbsoluteSize.X
		end
		
		if self.HorizontalAlignment == "Right" then
			xOffset = adorneeWidth - contentSize
		elseif self.HorizontalAlignment == "Center" then
			local halfPadding = ((#children-1)*absolutePadding) / 2
			
			xOffset = (adorneeWidth / 2) - ((contentSize / 2) + halfPadding) 			
		end
		
		for i, guiObject in ipairs(children) do	
			local yOffset = 0
			
			if self.VerticalAlignment == "Bottom" then
				yOffset = adorneeHeight - (guiObject.AbsoluteSize.Y) 
			elseif self.VerticalAlignment == "Center" then
				yOffset = (adorneeHeight / 2) - (guiObject.AbsoluteSize.Y / 2)
			end
			
			guiObject.Position = UDim2.fromOffset(xOffset + (i-1)*absolutePadding, yOffset)
			
			xOffset += guiObject.AbsoluteSize.X
		end
	else
		local absolutePadding = self.Padding.Offset + (adorneeHeight * self.Padding.Scale)

		local yOffset = 0 -- default / top align
		
		-- get content size
		local contentSize = 0
		for i, child in children do
			contentSize += child.AbsoluteSize.Y
		end
		
		if self.VerticalAlignment == "Bottom" then
			yOffset = adorneeHeight - contentSize
		elseif self.VerticalAlignment == "Center" then		
			local halfPadding = ((#children-1)*absolutePadding) / 2
			
			yOffset = (adorneeHeight / 2) - ((contentSize / 2) + halfPadding)		
		end
		
		for i, guiObject in ipairs(children) do
			local xOffset = 0
			
			if self.HorizontalAlignment == "Right" then
				xOffset = adorneeWidth - (guiObject.AbsoluteSize.X)
			elseif self.HorizontalAlignment == "Center" then
				xOffset = (adorneeWidth / 2) - (guiObject.AbsoluteSize.X / 2)
			end
			
			guiObject.Position = UDim2.fromOffset(xOffset, yOffset + (i-1)*absolutePadding)
			
			yOffset += guiObject.AbsoluteSize.Y
		end
	end
end

return CustomListLayout
