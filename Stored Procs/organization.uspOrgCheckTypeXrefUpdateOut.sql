USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgCheckTypeXrefUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgCheckTypeXref, it will not update the StatusFlag
	Tables: [organization].[OrgCheckTypeXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-11-08 - LBD - Modified, added StatusFlag
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCheckTypeXrefUpdateOut](
	 @piOrgId INT = -1
	,@piCheckTypeId INT = -1
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgCheckTypeXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgCheckTypeXref table (
		 OrgCheckTypeXrefId int
		,OrgId int
		,CheckTypeId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this xref to an org/checktype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgCheckTypeXref]
					WHERE OrgCheckTypeXrefId <> @piOrgCheckTypeXrefId
						AND OrgId = @piOrgId
						AND CheckTypeId = @piCheckTypeId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgCheckTypeXref]
			SET OrgId = CASE WHEN @piOrgId = -1 THEN OrgId ELSE @piOrgId END
				,CheckTypeId = CASE WHEN @piCheckTypeId = -1 THEN CheckTypeId ELSE @piCheckTypeId END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgCheckTypeXrefId
				,deleted.OrgId
				,deleted.CheckTypeId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgCheckTypeXref
			WHERE OrgCheckTypeXrefId = @piOrgCheckTypeXrefId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[OrgCheckTypeXref](OrgCheckTypeXrefId
			--,OrgId
			--,CheckTypeId
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgCheckTypeXrefId
			--,OrgId
			--,CheckTypeId
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @OrgCheckTypeXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgCheckTypeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgCheckTypeXrefId = OrgCheckTypeXrefId
			FROM @OrgCheckTypeXref;
		END
	END
	ELSE
		SELECT @piOrgCheckTypeXrefId = -3
END
