USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspOrgIPXrefUpdate]    Script Date: 1/2/2025 6:07:52 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIPXrefUpdate
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgIPXref
	Tables: [organization].[OrgIPXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspOrgIPXrefUpdate](
	 @piOrgIPXrefId INT
	,@piOrgId INT = -1
	,@pnvIP NVARCHAR(255) = N''
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgIPXref table (
		 OrgIPXrefId int
		,OrgId int
		,[IP] nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	
	--Will Not update this xref to an org/IPtype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgIPXref]
					WHERE OrgIPXrefId <> @piOrgIPXrefId
						AND OrgId = @piOrgId
						AND [IP] = @pnvIP) --2017-11-10
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgIPXref]
			SET OrgId = CASE WHEN @piOrgId = -1 THEN OrgId ELSE @piOrgId END
				,[IP] = CASE WHEN @pnvIP = N'' THEN [IP] ELSE @pnvIP END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT inserted.OrgIPXrefId
				,inserted.OrgId
				,inserted.[IP]
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @OrgIPXref
			WHERE OrgIPXrefId = @piOrgIPXrefId;
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
			SELECT ox.OrgIPXrefId, ox.OrgId, o.Name AS OrgName, o.OrgTypeId 
				,ox.[IP], ox.StatusFlag, ox.DateActivated, ox.UserName
			FROM @OrgIPXref ox
			INNER JOIN [organization].[Org] o on ox.OrgId = o.OrgId
		END
	END
	ELSE
		RAISERROR ('OrgId and IP combination already exists', 16, 1);
END
