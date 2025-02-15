USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [riskprocessingflow].[uspVaeSwitchCaseInsertOut]
	Created by: Chris Sharp
	Description: This procedure accepts the following parameters necessary to create a new 
		VaeSwitchCase entry.  

		 @pnvBriskPluginCode NVARCHAR(25) = 'VaeRtla'
		,@pnvVaeModelName NVARCHAR(50) = 'FNB RTLA V1.0'
		,@pnvSwitchCaseName NVARCHAR(100) = 'FNB RTLA V1.0 VaeRtla Case'
		,@pnvOrgName NVARCHAR(50) = 'FNBPA Bank'
		,@pnvOrgTypeName NVARCHAR(50) = 'Client'
		,@pnvUserName NVARCHAR(100) = N'VALID-xxx'

	Table: [riskprocessingflow].[BriskPlugin]
		,[riskprocessingflow].[VaeModel]
		,[riskprocessingflow].[VaeModelStatXref]
		,[stat].[Stat]

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-05-15 - CBS - VALID-968: Created
*****************************************************************************************/
ALTER   PROCEDURE [riskprocessingflow].[uspVaeSwitchCaseInsertOut](
     @pnvBriskPluginCode NVARCHAR(25)
	,@pnvVaeModelName NVARCHAR(50)
	,@pnvSwitchCaseName NVARCHAR(100)
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
		,@nvSwitchCaseName nvarchar(100) = @pnvSwitchCaseName
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iBriskPluginId int = 0
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

		--Output existing values in prep for insert back into [riskprocessingflow].[VaeSwitchCase] with new VaeModelId
		--Per Hal, we can't have two active switch rules with the same name
		--We can't have two active switch rules with the same OrgId and Priority (I think)
		IF (ISNULL(@iOrgId, -1) > -1
			AND ISNULL(@iBriskPluginId, -1) > -1
			AND ISNULL(@iVaeModelId, -1) > -1)
		BEGIN
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
			SELECT @nvSwitchCaseName AS CaseName
				,NULL AS CaseDesc
				,@iOrgId AS OrgId 
				,@iVaeModelId AS VaeModelId
				,@iPriority AS [Priority]
				,@dtDateActivated
				,@nvUserName AS UserName;	

			SELECT @piCaseId = CaseId 
			FROM @tblVaeSwitchCase;
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH
END
