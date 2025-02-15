USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [riskprocessingflow].[uspVaeModelUpdateOut]
	Created by: Chris Sharp
	Description: This procedure accepts the following parameters necessary to create a new 
		VaeBrisk or VaeRtla model.  It assumes a list of stats has already been populated 
		and passed into the proc.  

		 @pnvBriskPluginCode NVARCHAR(25) = N'VaeBrisk'
		,@pnvOldVaeModelName NVARCHAR(50) = 'KeyBank Mobile V1.0'
		,@pnvNewVaeModelName NVARCHAR(50) = 'KeyBank Mobile V2.0'
		,@pdBaseScore DECIMAL(28,12) = 10.00000
		,@pnvDescr NVARCHAR(255) = 'KeyBank Mobile V2.0 Updated BaseScore is 10.00000' 
		,@pnvUrlBase NVARCHAR(255) = N'http://192.168.70.199:8080/deployments' --PPS1
		,@pnvUrlPath NVARCHAR(150) = 'KEY.VAE.6449404963bd80b613e55fad'
		,@piStatusFlag INT = 1
		,@pbIsRegressionModel BIT = 1 (RTLA = 0, VaeBrisk = 1)
		,@pnvUserName NVARCHAR(100) = N'VALID-xxx'

	Table: [riskprocessingflow].[BriskPlugin]
		,[riskprocessingflow].[VaeModel]
		,[riskprocessingflow].[VaeModelStatXref]
		,[stat].[Stat]

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-05-15 - CBS - VALID-968: Created
*****************************************************************************************/
ALTER   PROCEDURE [riskprocessingflow].[uspVaeModelUpdateOut](
	 @pnvBriskPluginCode NVARCHAR(25) 
	,@pnvOldVaeModelName NVARCHAR(50) 
	,@pnvNewVaeModelName NVARCHAR(50) 
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
	,@piVaeModelId INT OUTPUT --Return to calling process
) AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblVaeModel table (VaeModelId int);
	DECLARE @tblVaeModelStatXref table (StatId int);
	DECLARE @iOldVaeModelId int = 0
		,@iNewVaeModelId int = 0
		,@nvBriskPluginCode nvarchar(25) = @pnvBriskPluginCode
		,@nvOldVaeModelName nvarchar(50) = ISNULL(@pnvOldVaeModelName, '')
		,@nvNewVaeModelName nvarchar(50) = ISNULL(@pnvNewVaeModelName, '')
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
		WHERE Code = @nvBriskPluginCode
			AND StatusFlag > 0;

		SELECT @iOldVaeModelId = VaeModelId
		FROM [riskprocessingflow].[VaeModel] 
		WHERE BriskPluginId = @iBriskPluginId
			AND [Name] = @nvOldVaeModelName
			AND StatusFlag > 0;
	
	--If we have a value for the BriskPluginId and OldVaeModelId and NewVaeModelName has a value empty, create a new record for a new VaeModel
	--NewVaeModelName, BaseScore, Descr, UrlPath, StatusFlag, IsRegressionModel DateActivated, UserName
	IF ISNULL(@iBriskPluginId, 0) > 0
		AND ISNULL(@iOldVaeModelId, 0) > 0
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

	--Insert new VaeModelId into VAEModelStatXref using StatLine associated with the OldVaeModelId 
	BEGIN TRY

		IF ISNULL(@iNewVaeModelId, 0) > 0
			AND ISNULL(@iOldVaeModelId, 0) > 0
			INSERT INTO [riskprocessingflow].[VaeModelStatXref](
				[VaeModelId]
				,[StatId]
				,[ParamOrd]
				,[StatusFlag]
				,[DateActivated]
				,[UserName]
			)
			OUTPUT inserted.StatId
			INTO @tblVaeModelStatXref
			SELECT @iNewVaeModelId
				,[StatId]
				,[ParamOrd]
				,@iStatusFlag AS StatusFlag
				,@dtDateActivated AS DateActivated
				,@nvUserName AS UserName
			FROM [riskprocessingflow].[VaeModelStatXref] 
			WHERE VaeModelId = @iOldVaeModelId
		
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH

	BEGIN TRY

		--Deactivated Old VaeModel associated with KeyBank Mobile V1.0
		UPDATE m
		SET m.StatusFlag = @iInactiveStatusFlag 
			,DateActivated = @dtDateActivated
			,UserName = @nvUserName
		FROM [riskprocessingflow].[VaeModel] m
		WHERE VaeModelId = @iOldVaeModelId;

	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH
	
	SELECT @piVaeModelId = @iNewVaeModelId;

END
