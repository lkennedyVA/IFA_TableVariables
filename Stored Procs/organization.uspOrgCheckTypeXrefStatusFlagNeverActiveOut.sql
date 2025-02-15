USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgCheckTypeXrefStatusFlagNeverActiveOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the OrgCheckTypeXref (Set StatusFlag to 3)
	Tables: [organization].[OrgCheckTypeXref]
		,[archive].[OrgCheckTypeXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCheckTypeXrefStatusFlagNeverActiveOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgCheckTypeXref]
			SET StatusFlag = 3
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
			----Anytime an update occurs we place an original copy in an archive table
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
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgCheckTypeXrefId = OrgCheckTypeXrefId
			FROM @OrgCheckTypeXref;
		END
	END
END
