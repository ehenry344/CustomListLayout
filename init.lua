--@author BostonWhaIer
--@created 11/27/2024
--@updated 11/28/2024

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
	_getInstances: (ListLayout)->{GuiObject},
	_positionInstances: (ListLayout)->()
}

type ListLayout = typeof(setmetatable({} :: {
	_adornee: GuiObject,
	_connections: {[GuiObject]: {RBXScriptConnection}},
	_contentSize: number,
		
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
	
	local self = {
		_adornee = adornee, 
		_connections = {},
		_contentSize = 0,
		
		Padding = config.Padding or UDim.new(0, 0), 
		FillDirection = config.FillDirection or "Vertical" :: FillDirection,
		SortOrder = config.SortOrder or "LayoutOrder" :: SortOrder,
		HorizontalAlignment = config.HorizontalAlignment or "Left" :: HorizontalAlignment,
		VerticalAlignment = config.VerticalAlignment or "Top" :: VerticalAlignment, 
	}
	
	setmetatable(self, CustomListLayout)
	
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
	
	-- gotta figure out how to not make this leak memory (aka setting everything in the table to nil to allow gc), typechecking is giving me issues with that :P
end

-- basically make it act like the real uilistlayout, so whenever stuff is added and stuff like that update the size. also handle the size update whe the object is created and such

-- TODO: add functionality that UIListLayouts also have where if you make some instance in its domain invisible itll update the position of the visible elements as if that elements
-- wasn't there.

function CustomListLayout:_hookAdornee()
	local function connectVisibility(guiObject: GuiObject)
		self._connections[guiObject] = {guiObject:GetPropertyChangedSignal("Visible"):Connect(function()
			self:_positionInstances()
		end)}
	end
	
	self._connections[self._adornee] = {}
	
	table.insert(self._connections[self._adornee], self._adornee.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			if self.FillDirection == "Horizontal" then
				self._contentSize += child.AbsoluteSize.X
			else
				self._contentSize += child.AbsoluteSize.Y
			end
			
			self:_positionInstances()
		end
	end))
	
	table.insert(self._connections[self._adornee], self._adornee.ChildRemoved:Connect(function(child)
		if child:IsA("GuiObject") then
			if self._connections[child] then
				for _, connection in ipairs(self._connections[child]) do
					connection:Disconnect()
				end
				
				self._connections[child] = nil
			end

			if self.FillDirection == "Horizontal" then
				self._contentSize -= child.AbsoluteSize.X
			else
				self._contentSize -= child.AbsoluteSize.Y
			end

			self:_positionInstances()
		end
	end))
	
	for _, child in ipairs(self:_getInstances()) do
		if self.FillDirection == "Horizontal" then
			self._contentSize += child.AbsoluteSize.X
		else
			self._contentSize += child.AbsoluteSize.Y
		end
		
		connectVisibility(child)
	end
	
	self:_positionInstances()
end

function CustomListLayout:_getInstances()
	local guiInstances = {}
	for _, v in pairs(self._adornee:GetChildren()) do
		if (v:IsA("GuiObject") and v.Visible then
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
	
	if self.FillDirection == "Horizontal" then
		local adorneeWidth = self._adornee.AbsoluteSize.X
		local absolutePadding = self.Padding.Offset + (adorneeWidth * self.Padding.Scale)
		
		local offset = 0 -- default / left align
		
		if self.HorizontalAlignment == "Right" then
			offset = adorneeWidth - self._contentSize
		elseif self.HorizontalAlignment == "Center" then
			local halfPadding = ((#children-1)*absolutePadding) / 2
			
			offset = (adorneeWidth / 2) - ((self._contentSize / 2) + halfPadding) 			
		end
		
		for i, guiObject in ipairs(children) do			
			guiObject.Position = UDim2.new(
				0, 
				offset + (i-1)*absolutePadding, 
				guiObject.Position.Y.Scale,
				guiObject.Position.Y.Offset 
			)
			
			offset += guiObject.AbsoluteSize.X
		end
	else
		local adorneeHeight = self._adornee.AbsoluteSize.Y
		local absolutePadding = self.Padding.Offset + (adorneeHeight * self.Padding.Scale)

		local offset = 0 -- default / top align

		if self.VerticalAlignment == "Bottom" then
			offset = adorneeHeight - self._contentSize
		elseif self.VerticalAlignment == "Center" then		
			local halfPadding = ((#children-1)*absolutePadding) / 2
			
			offset = (adorneeHeight / 2) - ((self._contentSize / 2) + halfPadding)		
		end

		for i, guiObject in ipairs(children) do
			guiObject.Position = UDim2.new(
				guiObject.Position.X.Scale, 
				guiObject.Position.X.Offset,
				0, 
				offset + (i-1)*absolutePadding
			)
			
			offset += guiObject.AbsoluteSize.Y
		end
	end
end

return CustomListLayout
