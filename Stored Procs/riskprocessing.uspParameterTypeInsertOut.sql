USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspParameterTypeInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[ParameterType]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterTypeInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piParameterTypeId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @ParameterType table (
       ParameterTypeId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   --Will Not update this ParameterType to a ParameterType already in use
   IF NOT EXISTS(SELECT 'X' 
                  FROM [riskprocessing].[ParameterType]
                  WHERE Name = @pnvName
                     OR Code = @pnvCode
                  )
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[ParameterType]
            OUTPUT inserted.ParameterTypeId
               ,inserted.Code
               ,inserted.Name
               ,inserted.Descr
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @ParameterType
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
         SET @piParameterTypeId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piParameterTypeId = ParameterTypeId
         FROM @ParameterType
      END
   END
   ELSE
      SELECT @piParameterTypeID = -3      
END
