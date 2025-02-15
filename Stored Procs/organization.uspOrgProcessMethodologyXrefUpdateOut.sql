USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgProcessMethodologyXrefUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgProcessMethodologyXref
		Returns -3 when attempting to update an existin xref to an 
		org/ProcessMethodology already in use

	Tables: [organization].[OrgProcessMethodologyXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2020-01-22 - LBD - Created
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgProcessMethodologyXrefUpdateOut](
	@piOrgId INT = -1
	,@piProcessMethodologyId INT = -1
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgProcessMethodologyXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgProcessMethodologyXref table (
		OrgProcessMethodologyXrefId int
		,OrgId int
		,ProcessMethodologyId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT = @@TRANCOUNT
		,@sSchemaName sysname = OBJECT_SCHEMA_NAME(@@PROCID);

	--Will Not update this xref to an org/ProcessMethodology already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgProcessMethodologyXref]
					WHERE OrgProcessMethodologyXrefId <> @piOrgProcessMethodologyXrefId
						AND OrgId = @piOrgId
						AND ProcessMethodologyId = @piProcessMethodologyId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgProcessMethodologyXref]
			SET OrgId = CASE WHEN @piOrgId = -1 THEN OrgId ELSE @piOrgId END
				,ProcessMethodologyId = CASE WHEN @piProcessMethodologyId = -1 THEN ProcessMethodologyId ELSE @piProcessMethodologyId END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgProcessMethodologyXrefId
				,deleted.OrgId
				,deleted.ProcessMethodologyId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgProcessMethodologyXref
			WHERE OrgProcessMethodologyXrefId = @piOrgProcessMethodologyXrefId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgProcessMethodologyXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgProcessMethodologyXrefId = OrgProcessMethodologyXrefId
			FROM @OrgProcessMethodologyXref;
		END
	END
	ELSE
		SELECT @piOrgProcessMethodologyXrefId = -3
END
