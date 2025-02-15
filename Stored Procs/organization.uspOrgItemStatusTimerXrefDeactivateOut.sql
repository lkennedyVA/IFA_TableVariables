USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgItemStatusTimerXrefDeActivateOut
	CreatedBy: Larry Dugger
	Description: This procedure will deactivate a xref record
	Tables: [organization].[OrgItemStatusTimerXref]

	History:
		2019-05-16 - LBD - Created
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgItemStatusTimerXrefDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgItemStatusTimerXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgItemStatusTimerXref table (
		 OrgItemStatusTimerXrefId int
		,OrgId int
		,TimerMinutes smallint
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[OrgItemStatusTimerXref]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.OrgItemStatusTimerXrefId
			,deleted.OrgId
			,deleted.TimerMinutes
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @OrgItemStatusTimerXref
		WHERE OrgItemStatusTimerXrefId = @piOrgItemStatusTimerXrefId;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgItemStatusTimerXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgItemStatusTimerXrefId = OrgItemStatusTimerXrefId
		FROM @OrgItemStatusTimerXref;
	END
END
