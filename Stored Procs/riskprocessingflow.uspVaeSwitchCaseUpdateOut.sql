USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [riskprocessingflow].[uspVaeSwitchCaseUpdateOut]
	Created by: Chris Sharp
	Description: This procedure accepts the following parameters necessary to update an 
		existing VaeSwitchCase entry.  

		 @pnvBriskPluginCode NVARCHAR(25) = 'VaeBrisk'
		,@pnvVaeModelName NVARCHAR(50) = 'KeyBank Mobile V2.0'
		,@pnvOldSwitchCaseName NVARCHAR(100) = 'KeyBank Mobile V1.0 VaeBrisk Case'
		,@pnvNewSwitchCaseName NVARCHAR(100) = 'KeyBank Mobile V2.0 VaeBrisk Case'
		,@pnvOrgName NVARCHAR(50) = 'KeyBank Mobile Location'
		,@pnvOrgTypeName NVARCHAR(50) = 'Location'
		,@pnvUserName NVARCHAR(100) = N'VALID-xxx'

	Table: [organization].[Org] 
		,[organization].[OrgType] 
		,[riskprocessingflow].[BriskPlugin]
		,[riskprocessingflow].[VaeModel]
		,[riskprocessingflow].[VaeModelStatXref]
		,[stat].[Stat]

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-05-15 - CBS - VALID-968: Created
*****************************************************************************************/
ALTER   PROCEDURE [riskprocessingflow].[uspVaeSwitchCaseUpdateOut](
     @pnvBriskPluginCode NVARCHAR(25)
	,@pnvVaeModelName NVARCHAR(50)
	,@pnvOldSwitchCaseName NVARCHAR(100)
	,@pnvNewSwitchCaseName NVARCHAR(100)
	,@pnvOrgName NVARCHAR(50) 
	,@pnvOrgTypeName NVARCHAR(50)
	,@pnvUserName NVARCHAR(100)
	,@piCaseId INT OUTPUT
)
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblVaeSwitchCase table (CaseId int);
	DECLARE @nvBriskPluginCode nvarchar(25) = @pnvBriskPluginCode 
		,@nvVaeModelName nvarchar(50) = @pnvVaeModelName
		,@nvOldSwitchCaseName nvarchar(100) = @pnvOldSwitchCaseName
	    ,@nvNewSwitchCaseName nvarchar(100) = @pnvNewSwitchCaseName
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iBriskPluginId int = 0
		,@iOldCaseId int
		,@iVaeModelId  int = 0
		,@iPriority int = 1000
		,@iRowCount int
		,@dtDateActivated datetime2(7) = CONVERT(datetime2(7),DATEADD(MINUTE, -3, SYSDATETIME()))
		,@iOrgId int
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME( @@PROCID );

	BEGIN TRY
	
		--Grabbing OrgId using the OrgName and OrgTypeName
		SELECT @iOrgId = OrgId 
		FROM [organization].[Org] o
		INNER JOIN [organization].[OrgType] ot
			ON o.OrgTypeId = ot.OrgTypeId
		WHERE o.[Name] = @pnvOrgName
			AND ot.[Name] = @pnvOrgTypeName
			AND o.StatusFlag > 0
			AND ot.StatusFlag > 0;

		SELECT @iBriskPluginId = BriskPluginId
		FROM [riskprocessingflow].[BriskPlugin] 
		WHERE Code = @nvBriskPluginCode
			AND StatusFlag > 0;

		SELECT @iVaeModelId = VaeModelId
		FROM [riskprocessingflow].[VaeModel] 
		WHERE BriskPluginId = @iBriskPluginId
			AND [Name] = @nvVaeModelName
			AND StatusFlag > 0;

		--This is to delete the old record using the CaseId
		SELECT @iOldCaseId = CaseId 
		FROM [riskprocessingflow].[VaeSwitchCase]
		WHERE CaseName = @nvOldSwitchCaseName;
	
	IF ISNULL(@iOldCaseId, 0) > 0
	BEGIN
		--Output existing values in prep for insert back into [riskprocessingflow].[VaeSwitchCase] with new VaeModelId
		--Per Hal, we can't have two active switch rules with the same name
		--We can't have two active switch rules with the same OrgId and Priority (I think)
		INSERT INTO [riskprocessingflow].[VaeSwitchCase](
			 CaseName
			,CaseDesc
			,OrgId
			,VaeModelId
			,[Priority]
			,DateActivated
			,UserName
		)
		OUTPUT inserted.CaseId
		INTO @tblVaeSwitchCase
		SELECT @nvNewSwitchCaseName AS CaseName
			,CaseDesc
			,OrgId 
			,@iVaeModelId AS VaeModelId
			,@iPriority AS [Priority]
			,@dtDateActivated
			,@nvUserName AS UserName
		FROM [riskprocessingflow].[VaeSwitchCase] 
		WHERE CaseId = @iOldCaseId;

		SET @iRowCount = @@ROWCOUNT;

		IF ISNULL(@iRowCount, 0) > 0
		BEGIN
			--DELETE Existing CaseId using the CaseId we gathered earlier
			DELETE x
			FROM [riskprocessingflow].[VaeSwitchCase] x
			WHERE CaseId = @iOldCaseId;

			SELECT @piCaseId = CaseId
			FROM @tblVaeSwitchCase;
		END
	END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH
END
