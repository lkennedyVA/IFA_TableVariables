USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspParameterValueInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[ParameterValue]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterValueInsertOut](
    @pnvValue NVARCHAR(512)
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piParameterValueId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @ParameterValue table (
       ParameterValueId int
      ,Value nvarchar(512)
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @piParameterValueId = 0;
   --Will Not update this ParameterValue to a ParameterValue already in use
   SELECT @piParameterValueId = ParameterValueId
   FROM [riskprocessing].[ParameterValue]
   WHERE Value = @pnvValue;
	IF ISNULL(@piParameterValueId,0) = 0 
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[ParameterValue]
            OUTPUT inserted.ParameterValueId
               ,inserted.Value
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @ParameterValue
         SELECT @pnvValue
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piParameterValueId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piParameterValueId = ParameterValueId
         FROM @ParameterValue
      END
   END   
END
