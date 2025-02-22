USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIPXrefUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgIPXref, it will not update the StatusFlag
	Tables: [organization].[OrgIPXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-11-08 - LBD - Modified, added StatusFlag
		2017-11-10 - CBS - Modified, added [IP] = @pnvIP to not exists clause
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgIPXrefUpdateOut](
	 @piOrgId INT = -1
	,@pnvIP NVARCHAR(255) = N''
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgIPXrefId INT OUTPUT
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
		,@sSchemaName nvarchar(128) = N'organization';
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
			OUTPUT deleted.OrgIPXrefId
				,deleted.OrgId
				,deleted.[IP]
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgIPXref
			WHERE OrgIPXrefId = @piOrgIPXrefId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgIPXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgIPXrefId = OrgIPXrefId
			FROM @OrgIPXref;
		END
	END
	ELSE
		SELECT @piOrgIPXrefId = -3
END
