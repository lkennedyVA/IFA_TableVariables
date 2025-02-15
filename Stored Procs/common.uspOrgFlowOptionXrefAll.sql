USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [uspOrgFlowOptionXrefAll]
	CreatedBy: Larry Dugger
	Description: Take an OrgId or Org Name and return the FlowOptions associated with it.
      With respect to Flowoption, how does it roll up? It uses the following formula:
         the check types indicated by OrgFlowoptionXref are absolute if any record at 
         this level has a StatusFlag = 2. Other wise the Flowoptions are cumulative...i.e.
         if defined at a parent they exist for the child.
	Tables: [organization].[OrgFlowOptionXref]
	   ,[common].[FlowOption]
	
	Functions: [common].[ufnUpDimensionByOrgIdILTF]
	
	History:
		2015-02-23 - LBD - Created 
		2015-06-02 - LBD - Modified, uses new function to cover origin of flow options
		2016-07-07 - LBD - Modified, uses the actual OrgId for Top
		2017-11-07 - LBD - Modified, added DateActivated and UserName.
		2018-03-20 - CBS - Modified, replacing [common].[ufnOrgFlowOptionXrefByOrgId2] with
			[common].[ufnOrgFlowOptionXrefByOrgId], adjsuted to use more efficient function
*****************************************************************************************/
ALTER PROCEDURE [common].[uspOrgFlowOptionXrefAll]
AS
BEGIN
	DECLARE @DownOrgList table(
		 LevelId int not null
		,ParentId int null
		,OrgId int not null
		,OrgName nvarchar(255) not null
		,TypeId int not null
		,[Type] nvarchar(50) not null
		,StatusFlag int not null
		);
	DECLARE @FlowOptionList table(
		 OrgFlowOptionXrefId int not null
		,LevelId int not null
		,ParentId int null
		,OrgId int not null
		,OrgName nvarchar(255) not null
		,FlowOptionId int not null
		,FlowOptionValue nvarchar(50) null
		,FlowOptionCode nvarchar(25) not null
		,FlowOptionName nvarchar(50) not null
		,StatusFlag int not null
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iOrgId int
		,@iOrgDimensionid int = [common].[ufnDimension]('Organization');
	SELECT @iOrgId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'Top'
		AND Name = 'Valid Systems Inc';

	INSERT INTO @DownOrgList(LevelId,ParentId,OrgId,OrgName,TypeId,[Type],StatusFlag)
	SELECT LevelId,ParentId,OrgId,OrgName,TypeId,[Type],StatusFlag 
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionid);

	INSERT INTO @FlowOptionList(OrgFlowOptionXrefId,LevelId,ParentId,OrgId,OrgName,FlowOptionId
		,FlowOptionValue,FlowOptionCode,FlowOptionName,StatusFlag,DateActivated,UserName)
	SELECT ofox.OrgFlowOptionXrefId,ofox.LevelId,ofox.ParentId,ofox.OrgId,ofox.OrgName,ofox.FlowOptionId
		,ofox.FlowOptionValue,ofox.FlowOptionCode,ofox.FlowOptionName,ofox.StatusFlag,ofox.DateActivated,ofox.UserName
	FROM @DownOrgList dol
	CROSS APPLY [common].[ufnOrgFlowOptionXrefByOrgId](dol.OrgId) ofox; --2018-03-20

	SELECT DISTINCT OrgFlowOptionXrefId
		,LevelId
		,ParentId
		,OrgId
		,OrgName
		,FlowOptionId
		,FlowOptionValue
		,FlowOptionCode
		,FlowOptionName
		,StatusFlag
		,DateActivated
		,UserName
	FROM @FlowOptionList
	ORDER BY OrgId,ParentId;
END
