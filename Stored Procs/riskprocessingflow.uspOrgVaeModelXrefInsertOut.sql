USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [riskprocessingflow].[uspOrgVaeModelXrefInsertOut]
	Created by: Chris Sharp
	Description: Inserts a record into riskprocessingflow.OrgVaeModelXref associating 
		an organization with an existing VaeModelId

	Table: [organization].[Org]
		,[riskprocessingflow].[OrgVaeModelXrefInsertOut]

	History:
		2020-09-01 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [riskprocessingflow].[uspOrgVaeModelXrefInsertOut](
	 @piOrgId INT
	,@piVaeModelId INT
	,@pbTestFlag BIT = 0
	,@pnvUserName NVARCHAR(100)
	,@piOrgVaeModelXrefId INT OUTPUT
) 
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblOrgVaeModelXref table(
		OrgVaeModelXrefId int
		,OrgId int
		,VaeModelId int
		,TestFlag int
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
		,UserName nvarchar(100) not null
	);				
	DECLARE @iOrgId int = @piOrgId
		,@iVaeModelId int = @piVaeModelId
		,@bTestFlag bit = @pbTestFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iOrgVaeModelXrefId int = -1
		,@iBriskPluginId int = -1
		,@dtDateActivated datetime2(7) = SYSDATETIME()
		,@iStatusFlag int = 1
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'import'
		,@iCurrentTransactionLevel int = @@TRANCOUNT; 

	SELECT @iOrgVaeModelXrefId = OrgVaeModelXrefId
	FROM [riskprocessingflow].[OrgVaeModelXref] x
	WHERE x.OrgId = @iOrgId
		AND x.VaeModelId = @iVaeModelId
		AND x.StatusFlag = @iStatusFlag;

	IF ISNULL(@iOrgVaeModelXrefId, -1) = -1
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [riskprocessingflow].[OrgVaeModelXref](
				 OrgId
				,VaeModelId
				,TestFlag
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.OrgVaeModelXrefId
				,inserted.OrgId
				,inserted.VaeModelId
				,inserted.TestFlag
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblOrgVaeModelXref
			SELECT @iOrgId AS OrgId
				,@iVaeModelId AS VaeModelId
				,@bTestFlag AS TestFlag
				,@iStatusFlag AS StatusFlag
				,@dtDateActivated AS DateActivated
				,@nvUserName AS UserName
			FROM [organization].[Org] o
			WHERE o.OrgId = @iOrgId;	
				
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW
		END CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgVaeModelXrefId = OrgVaeModelXrefId
			FROM @tblOrgVaeModelXref;
		END
	END
	ELSE
		SET @piOrgVaeModelXrefId = @iOrgVaeModelXrefId;
END
