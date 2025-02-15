USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgItemStatusTimerXrefInsertOut
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new xref record
	Tables: [organization].[OrgItemStatusTimerXref]
	History:
		2019-05-16 - LBD - Created
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgItemStatusTimerXrefInsertOut](
	 @piOrgId INT
	,@psiTimerMinutes SMALLINT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[OrgItemStatusTimerXref]
			OUTPUT inserted.OrgItemStatusTimerXrefId
			,inserted.OrgId
			,inserted.TimerMinutes
			,inserted.StatusFlag
			,inserted.DateActivated
			,inserted.UserName
			INTO @OrgItemStatusTimerXref
		SELECT @piOrgId
			,@psiTimerMinutes
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgItemStatusTimerXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > 0
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgItemStatusTimerXrefId = OrgItemStatusTimerXrefId
		FROM @OrgItemStatusTimerXref
	END
END
