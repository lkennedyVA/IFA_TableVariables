USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspLadderTopXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-11-12
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[LadderTopXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-11-12 - LBD - Created.
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopXrefInsertOut](
    @pnvTitle NVARCHAR(255)
   ,@piLadderTopId INT
   ,@pnvLadderSuccessValue NVARCHAR(512)
   ,@piLadderSuccessLTXId INT
   ,@piLadderContinueLTXId INT
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piLadderTopXrefId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @LadderTopXref table (
       LadderTopXrefId int
      ,Title nvarchar(255)
      ,LadderTopId int
	   ,LadderSuccessValue nvarchar(512)
	   ,LadderSuccessLTXId int
	   ,LadderContinueLTXId int
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   ----Will Not update this LadderTopXref to a LadderTopXref already in use
   --IF NOT EXISTS(SELECT 'X' 
   --               FROM [riskprocessing].[LadderTopXref]
   --               WHERE Title = @pnvTitle
   --                  AND LadderId = @piLadderId
   --                  AND LadderTopId = @piLadderTopId
   --               )
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[LadderTopXref]
            OUTPUT inserted.LadderTopXrefId
               ,inserted.Title
               ,inserted.LadderTopId
               ,inserted.LadderSuccessValue
               ,inserted.LadderSuccessLTXId
               ,inserted.LadderContinueLTXId
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @LadderTopXref
         SELECT @pnvTitle
            ,@piLadderTopId
            ,@pnvLadderSuccessValue
            ,@piLadderSuccessLTXId
            ,@piLadderContinueLTXId
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piLadderTopXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piLadderTopXrefId = LadderTopXrefId
         FROM @LadderTopXref
      END
   END
   --ELSE
   --   SELECT @piLadderTopXrefID = -3      
END
