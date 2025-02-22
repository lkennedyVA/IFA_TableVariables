USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspRCInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[RC]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piRCId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @RC table (
       RCId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,StatusFlag int
      ,DateActivated datetime2(7)
		,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskcontrol';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [riskprocessing].[RC]
         OUTPUT inserted.RCId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.StatusFlag
            ,inserted.DateActivated
				,inserted.UserName
         INTO @RC
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piRCId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piRCId = RCId
      FROM @RC
   END
END
