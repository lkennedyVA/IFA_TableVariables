USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleBreakDataInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new record
	Tables: [ifa].[RuleBreakData]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspRuleBreakDataInsertOut](
	 @pbiItemId BIGINT
	,@pnvCode NVARCHAR(25)
   ,@pnvMessage NVARCHAR(255)
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piRuleBreakDataId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @RuleBreakData table (
		 RuleBreakDataId bigint
		,ItemId bigint
		,Code nvarchar(25)
		,[Message] nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128) = N'ifa';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [ifa].[RuleBreakData]
         OUTPUT inserted.RuleBreakDataId
            ,inserted.ItemId
            ,inserted.Code
            ,inserted.[Message]
            ,inserted.StatusFlag
            ,inserted.DateActivated 
				,inserted.UserName
         INTO @RuleBreakData
      SELECT @pbiItemId
			,@pnvCode
			,@pnvMessage
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piRuleBreakDataId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piRuleBreakDataId = RuleBreakDataId
      FROM @RuleBreakData;
	END
END
