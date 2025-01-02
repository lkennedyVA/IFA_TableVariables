USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspClientUpdate]    Script Date: 1/2/2025 6:03:20 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspClientUpdate
	CreatedBy: Larry Dugger
	Descr: This procedure will update the Client org
	Tables: [organization].[Org]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2017-11-21 - LBD - Created
		2018-01-31 - CBS - Modified, updated insert of .deleted to .inserted 
*****************************************************************************************/
ALTER PROCEDURE [command].[uspClientUpdate](
	 @piOrgId INT
	,@pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Org table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,ParentOrgId int
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this Org to a Org already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[Org]
					WHERE OrgId <> @piOrgId
						AND [Name] = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE o
			SET o.[Code] = CASE WHEN @pnvCode = N'' THEN o.[Code] ELSE @pnvCode END
				,o.[Name] = CASE WHEN @pnvName = N'' THEN o.[Name] ELSE @pnvName END
				,o.[Descr] = CASE WHEN @pnvDescr = N'' THEN o.[Descr] ELSE @pnvDescr END
				,o.DateActivated = SYSDATETIME()
				,o.StatusFlag = CASE WHEN ISNULL(@piStatusFlag,-1) = -1 THEN o.StatusFlag ELSE @piStatusFlag END
				,o.UserName = @pnvUserName
			OUTPUT inserted.OrgId --2018-01-31
				,inserted.OrgTypeId
				,inserted.Code
				,inserted.[Name]
				,inserted.Descr
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				,ox.OrgParentId
			INTO @Org
			FROM [organization].[Org] o
			INNER JOIN [organization].[OrgXref] ox on o.OrgId = ox.OrgChildId
			WHERE o.OrgId = @piOrgId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT OrgId, Code AS OrgCode, [Name] AS OrgName, Descr AS OrgDescr
			,ParentOrgId AS ParentOrgId, StatusFlag, DateActivated, UserName
			FROM @Org;
		END
	END
	ELSE
		RAISERROR ('An Org with this name already exists',16,1);
END
