USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspMiscInfoInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [ifa].[Misc] with the associated Misc types (MiscData1-4)
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspMiscInfoInsertOut](
	 @pbiProcessId BIGINT
	,@ptblMiscInfo [ifa].[MiscInfoType] READONLY
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@pbiMiscInfoId BIGINT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @Misc table (
       MiscId bigint
      ,ProcessId bigint
		,MiscTypeId int
		,MiscInfo nvarchar(255)
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
   DECLARE @iStatusFlag int =	[common].[ufnStatusFlag]('Active')
		,@iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128) = N'ifa';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
		--INSERT What is new
		INSERT INTO [ifa].[Misc]
			OUTPUT inserted.MiscId
				,inserted.ProcessId
				,inserted.MiscTypeId
				,inserted.MiscInfo
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @Misc
		SELECT @pbiProcessId
			,mt.MiscTypeId
			,mi.[Text]
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName
		FROM @ptblMiscInfo mi
		INNER JOIN [common].[MiscType] mt on mi.TextType = mt.Code
		WHERE mt.StatusFlag = @iStatusFlag;
	END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @pbiMiscInfoId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW;
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
		SELECT @pbiMiscInfoId = MAX(MiscId)
      FROM @Misc;
   END
END
