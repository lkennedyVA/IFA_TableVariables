USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspParameterInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[Parameter]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterInsertOut](
    @piParameterTypeId INT
   ,@pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@pbOtput BIT
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piParameterId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @Parameter table (
       ParameterId int
      ,ParameterTypeId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,Otput bit
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   --Will Not update this Parameter to a Parameter already in use
   IF NOT EXISTS(SELECT 'X' 
                  FROM [riskprocessing].[Parameter]
                  WHERE Name = @pnvName
                     OR Code = @pnvCode
                  )
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[Parameter]
            OUTPUT inserted.ParameterId
               ,inserted.ParameterTypeId
               ,inserted.Code
               ,inserted.Name
               ,inserted.Descr
               ,inserted.Otput
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @Parameter
         SELECT @piParameterTypeId
            ,@pnvCode
            ,@pnvName
            ,@pnvDescr
            ,@pbOtput
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piParameterId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piParameterId = ParameterId
         FROM @Parameter
      END
   END
   ELSE
      SELECT @piParameterID = -3      
END
