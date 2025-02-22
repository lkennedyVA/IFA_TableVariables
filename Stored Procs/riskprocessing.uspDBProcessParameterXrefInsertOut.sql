USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspDBProcessParameterXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[DBProcessParameterXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessParameterXrefInsertOut](
    @piDBProcessId INT
   ,@piParameterId INT
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piDBProcessParameterXrefId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @DBProcessParameterXref table (
       DBProcessParameterXrefId int
      ,DBProcessId int
      ,ParameterId int
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @piDBProcessParameterXrefId = 0;
   --Will Not update this DBProcessParameterXref to a DBProcessParameterXref already in use
   SELECT @piDBProcessParameterXrefId = DBProcessParameterXrefId
   FROM [riskprocessing].[DBProcessParameterXref]
   WHERE DBProcessId = @piDBProcessId
      AND ParameterId = @piParameterId;
	IF @piDBProcessParameterXrefId = 0
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[DBProcessParameterXref]
            OUTPUT inserted.DBProcessParameterXrefId
               ,inserted.DBProcessId
               ,inserted.ParameterId
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @DBProcessParameterXref
         SELECT @piDBProcessId
            ,@piParameterId
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piDBProcessParameterXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piDBProcessParameterXrefId = DBProcessParameterXrefId
         FROM @DBProcessParameterXref
      END
   END
 END
