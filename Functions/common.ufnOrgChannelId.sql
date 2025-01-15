USE [IFA]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: [common].[ufnOrgChannelId]
	Created By: Chris Sharp
	Description: Take an Org Id and return the Id for its Channel, assumes the Dimension is
		'Channel'

	Tables: [organization].[Org]
		,[organization].[OrgXref] 

	History:
		2017-01-16 - CBS - Created
		2017-03-20 - LBD - Modified, returns actual OPS ChannelId 
			1 - ChannelTeller	- Teller
			2 - ChannelATM		- ATM
			3 - ChannelMobile	- Mobile
		2018-03-14 - LBD - Modified, uses more efficient function
		2019-05-30 - LBD - Modified, 4x more efficient
		2025-01-15 - LXK - Took out double join and reordered tables to get same results
*****************************************************************************************/
ALTER   FUNCTION [common].[ufnOrgChannelId](
    @piOrgId INT
)
RETURNS INT
AS
BEGIN
	DECLARE @iChannelId int = 0
		,@iChannelDimensionId int = [common].[ufnDimension]('Channel')
		,@iOrgId int = @piOrgId;
	
SELECT @iChannelId = CONVERT(INT, op.Code)
FROM [organization].[OrgXref] ox 
INNER JOIN [organization].[Org] op on op.OrgId = ox.OrgParentId and op.OrgId = ox.OrgChildId
WHERE op.OrgId = @iOrgId AND ox.DimensionId = @iChannelDimensionId;

	RETURN @iChannelId
END
GO


