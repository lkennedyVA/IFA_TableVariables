USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLoadDBEnums
	CreatedBy: Larry Dugger
	Date: 2015-05-26
	Descr: This procedure is a test load
	Tables: [organization].[Org]
   
	Functions: [common].[ufnOrgCheckTypeXrefByOrgId]
		,[common].[ufnOrgIdTypeXrefByOrgId]
	History:
		2015-05-26 - LBD - Created
		2015-05-26 - LBD - Modified, use table variable
		2016-03-07 - LBD - Modified, added in organization dimension
		2016-07-07 - LBD - Modified, completely re-wrote. Look at [condensed].[uspLoadDBEnum]
*****************************************************************************************/
ALTER PROCEDURE [common].[uspLoadDBEnums]
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @DBEnums table (
		 OrgId int not null
		,[Value] nvarchar(255) not null
		,Code nvarchar(25) not null
		,Name nvarchar(50) not null
	);
	INSERT INTO @DBEnums(OrgId,[Value],Code,Name)
	SELECT OrgId,[Value],Code,Name
	FROM [condensed].[DbEnum];

	SELECT OrgId,[Value],Code,Name
	FROM @DBEnums
	ORDER BY OrgId, [Value];
END
