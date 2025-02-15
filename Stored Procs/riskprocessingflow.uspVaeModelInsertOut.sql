USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [riskprocessingflow].[uspVaeModelInsertOut]
	Created by: Chris Sharp
	Description: This procedure accepts the following parameters necessary to create a new 
		VaeBrisk or VaeRtla model.  It assumes a list of stats has already been populated 
		and passed into the proc.  

		 @pnvBriskPluginCode NVARCHAR(25) = N'VaeRtla'
		,@pnvVaeModelName NVARCHAR(50) = 'FNB RTLA V1.0'
		,@pdBaseScore DECIMAL(28,12) = 1.10000
		,@pnvDescr NVARCHAR(255) = 'FNB RTLA V1.0 Initial BaseScore is 10.00000' 
		,@pnvUrlBase NVARCHAR(255) = N'http://192.168.70.199:8080/deployments' --PPS1'
		,@pnvUrlPath NVARCHAR(150) = 'FNB.RTLA.645a45d6cf25b830970f3254'
		,@piStatusFlag INT = 1
		,@pbIsRegressionModel BIT = 0 (RTLA = 0, VaeBrisk = 1)
		,@pnvUserName NVARCHAR(100) = N'VALID-xxx'
		,@ptblStat [ifa].[NameValueType] READONLY 

	Table: [riskprocessingflow].[BriskPlugin]
		,[riskprocessingflow].[VaeModel]
		,[riskprocessingflow].[VaeModelStatXref]
		,[stat].[Stat]

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-05-15 - CBS - VALID-968: Created
*****************************************************************************************/
ALTER   PROCEDURE [riskprocessingflow].[uspVaeModelInsertOut](
	 @pnvBriskPluginCode NVARCHAR(25) 
	,@pnvVaeModelName NVARCHAR(50)
	,@pdBaseScore DECIMAL(28,12) 
	,@pnvDescr NVARCHAR(255) 
	,@pnvUrlBase NVARCHAR(255)
	,@pnvUrlPath NVARCHAR(150) 
	,@pnvUrlMethod NVARCHAR(50) = NULL --Assign default
	,@pnvApiToken NVARCHAR(50) = NULL
	,@pnvApiUserName NVARCHAR(50) = NULL
	,@piStatusFlag INT 
	,@pbIsRegressionModel BIT 
	,@pnvUserName NVARCHAR(100) 
	,@ptblStat [ifa].[NameValueType] READONLY --Pre-load with list of stats associated with VAE / RTLA model
	,@piVaeModelId INT OUTPUT --Return to calling process
) AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblVaeModel table (VaeModelId int);
	DECLARE @iNewVaeModelId int = 0
		,@nvBriskPluginCode nvarchar(25) = @pnvBriskPluginCode
		,@nvNewVaeModelName nvarchar(50) = ISNULL(@pnvVaeModelName, '')
		,@dBaseScore decimal(28,12) = @pdBaseScore
		,@nvDescr nvarchar(255) = @pnvDescr 
		,@nvUrlBase nvarchar(255) = ISNULL(@pnvUrlBase, 'http://192.168.65.208:8080/deployments') --VIP
		,@nvUrlPath nvarchar(150) = @pnvUrlPath
		,@nvUrlMethod nvarchar(50) = ISNULL(@pnvUrlMethod, 'predictions')
		,@nvApiToken nvarchar(50) = @pnvApiToken
		,@nvApiUserName nvarchar(50) = @pnvApiUserName
		,@iStatusFlag int = @piStatusFlag
		,@bIsRegressionModel bit = @pbIsRegressionModel
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iBriskPluginId int = 0
		,@iInactiveStatusFlag int = 0
		,@dtDateActivated datetime2(7) = CONVERT(datetime2(7), DATEADD(MINUTE, -3, SYSDATETIME()))
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME( @@PROCID );

	BEGIN TRY

		SELECT @iBriskPluginId = BriskPluginId
		FROM [riskprocessingflow].[BriskPlugin] 
		WHERE Code = @nvBriskPluginCode;

		--If we have a value for the BriskPluginId and OldVaeModelId and NewVaeModelName has a value empty, create a new record for a new VaeModel
		--NewVaeModelName, BaseScore, Descr, UrlPath, StatusFlag, IsRegressionModel DateActivated, UserName
		IF ISNULL(@iBriskPluginId, 0) > 0
			AND ISNULL(@nvNewVaeModelName, '') <> ''
		BEGIN
			--Create new VaeModel and output the new VaeModelId for use in inserting into VaeModelStatXref
			INSERT INTO [riskprocessingflow].[VaeModel](
				 BriskPlugInId
				,[Name]
				,BaseScore
				,Descr
				,UrlBase
				,UrlPath
				,UrlMethod
				,ApiToken
				,ApiUserName
				,StatusFlag
				,DateActivated
				,UserName
				,IsRegressionModel
			)
			OUTPUT inserted.VaeModelId 
			INTO @tblVaeModel
			SELECT @iBriskPluginId AS BriskPluginId
				,@nvNewVaeModelName AS [Name]
				,@dBaseScore AS BaseScore
				,@nvDescr AS Descr
				,@nvUrlBase AS UrlBase
				,@nvUrlPath AS UrlPath
				,@nvUrlMethod AS UrlMethod
				,@nvApiToken AS ApiToken
				,@nvApiUserName AS ApiUserName
				,@iStatusFlag AS StatusFlag
				,@dtDateActivated AS DateActivated
				,@nvUserName AS UserName
				,@bIsRegressionModel AS IsRegressionModel;

			--Assign the VaeModelId to @iNewVaeModelId
			SELECT @iNewVaeModelId = VaeModelId
			FROM @tblVaeModel;
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH

	--Insert new VaeModelId into VAEModelStatXref using StatLine passed in via @ptblStat
	BEGIN TRY

		IF ISNULL(@iNewVaeModelId, 0) > 0
			INSERT INTO [riskprocessingflow].[VaeModelStatXref](
				[VaeModelId]
				,[StatId]
				,[ParamOrd]
				,[StatusFlag]
				,[DateActivated]
				,[UserName]
			)
			SELECT @iNewVaeModelId
				,s.[StatId]
				,0 AS ParamOrder
				,@iStatusFlag AS StatusFlag
				,@dtDateActivated AS DateActivated
				,@nvUserName AS UserName
			FROM @ptblStat x
			LEFT JOIN [stat].[Stat] s 
				ON x.[Name] = s.[Name]
			ORDER BY StatId ASC;

	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH
	
	SELECT @piVaeModelId = @iNewVaeModelId;

END
